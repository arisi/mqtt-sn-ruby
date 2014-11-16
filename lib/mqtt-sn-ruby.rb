#!/usr/bin/env ruby
# encode: UTF-8

require "pp"
require 'socket'
require 'json'

class MqttSN

  Nretry = 5  # Max retry
  Tretry = 10 # Timeout before retry 

  CONNECT_TYPE   =0x04
  CONNACK_TYPE   =0x05
  WILLTOPICREQ_TYPE=0x06
  WILLTOPIC_TYPE =0x07
  WILLMSGREQ_TYPE=0x08
  WILLMSG_TYPE   =0x09
  REGISTER_TYPE  =0x0A
  REGACK_TYPE    =0x0B
  PUBLISH_TYPE   =0x0C
  PUBACK_TYPE    =0x0D
  PUBCOMP_TYPE   =0x0E
  PUBREC_TYPE    =0x0F
  PUBREL_TYPE    =0x10
  SUBSCRIBE_TYPE =0x12
  SUBACK_TYPE    =0x13
  UNSUBSCRIBE_TYPE=0x14
  UNSUBACK_TYPE  =0x15
  PINGREQ_TYPE   =0x16
  PINGRESP_TYPE  =0x17
  DISCONNECT_TYPE=0x18
  WILLTOPICUPD_TYPE=0x1A
  WILLTOPICRESP_TYPE=0x1B
  WILLMSGUPD_TYPE =0x1C
  WILLMSGRESP_TYPE=0x1D

  RETAIN_FLAG=0x10
  WILL_FLAG  =0x08
  CLEAN_FLAG =0x04
  QOSM1_FLAG =0x60
  QOS2_FLAG  =0x40
  QOS1_FLAG  =0x20
  QOS0_FLAG  =0x00

  @@msg_id=1

  def initialize(hash={})
      @server=hash[:server]||"127.0.0.1"
      @port=hash[:port]||1883
      @debug=hash[:debug]
      @state=:inited
      @will_topic=nil
      @will_msg=nil
      @id="?"
      @topics={} #hash of registered topics is stored here
      @iq = Queue.new
      @s = UDPSocket.new
      @t=Thread.new do
        recv_thread
      end
      puts "opened ok"
      pp @s
  end

  def close
    proc { puts "DESTROY OBJECT #{bar}" }
  end

  def hexdump data
    raw=""
    data.each_byte do |b|
      raw=raw+"," if raw!=""
      raw=raw+sprintf("%02X",b)
    end
    raw
  end

  def send_packet m
    msg=" "
    len=1
    m.each_with_index do |b,i|
      msg[i+1]=b.chr
      len+=1
    end
    msg[0]=len.chr
    @s.send(msg, 0, @server, @port)
    hexdump msg
  end

  def send type,hash={},&block
    puts ""
    if @state!=:connected and type!=:connect and type!=:will_topic  and type!=:will_msg
      raise "Error: Cannot #{type} while unconnected, send :connect first!"
    end
    case type
    when :connect
      raise "Need :id, it is required at :connect!" if not hash[:id]
      flags=0 
      flags+=CLEAN_FLAG if hash[:clean]
      flags+=RETAIN_FLAG if hash[:retain]
      flags+=WILL_FLAG if @will_topic
      p=[CONNECT_TYPE,flags,0x01,0,30]
      hash[:id].each_byte do |b|
        p<<b
      end
      @id=hash[:id]
    when :register 
      raise "Need :topic to Publish!" if not hash[:topic]
      p=[REGISTER_TYPE,0,0,@@msg_id >>8 ,@@msg_id & 0xff]
      hash[:topic].each_byte do |b|
        p<<b
      end
      @@msg_id+=1
    when :register_ack
      p=[REGACK_TYPE,hash[:topic_id]>>8 ,hash[:topic_id] & 0xff,hash[:msg_id]>>8 ,hash[:msg_id] & 0xff,hash[:return_code]]
    when :publish_ack
      p=[PUBACK_TYPE,hash[:topic_id]>>8 ,hash[:topic_id] & 0xff,hash[:msg_id]>>8 ,hash[:msg_id] & 0xff,hash[:return_code]]
    when :pub_rec
      p=[PUBREC_TYPE,hash[:msg_id]>>8 ,hash[:msg_id] & 0xff]
    when :pub_comp
      p=[PUBCOMP_TYPE,hash[:msg_id]>>8 ,hash[:msg_id] & 0xff]
    when :will_topic 
      raise "Need :topic to :will_topic" if not hash[:topic]
      p=[WILLTOPIC_TYPE,0]
      hash[:topic].each_byte do |b|
        p<<b
      end
    when :will_topic_upd 
      raise "Need :topic to :will_topic_upd" if not hash[:topic]
      p=[WILLTOPICUPD_TYPE,0]
      hash[:topic].each_byte do |b|
        p<<b
      end
    when :will_msg 
      raise "Need :msg to :will_msg" if not hash[:msg]
      p=[WILLMSG_TYPE]
      hash[:msg].each_byte do |b|
        p<<b
      end
    when :will_msg_upd
      raise "Need :msg to :will_msg_upd" if not hash[:msg]
      p=[WILLMSGUPD_TYPE]
      hash[:msg].each_byte do |b|
        p<<b
      end

    when :subscribe 
      raise "Need :topic to :subscribe" if not hash[:topic]
      qos=hash[:qos]||0
      flags=0 
      if qos==-1
        flags+=QOSM1_FLAG
      else
        flags+=QOS1_FLAG*qos 
      end
      p=[SUBSCRIBE_TYPE,flags,@@msg_id >>8 ,@@msg_id & 0xff]
      hash[:topic].each_byte do |b|
        p<<b
      end
      @@msg_id+=1


    when :publish
      raise "Need :topic_id to Publish!" if not hash[:topic_id]
      qos=hash[:qos]||0
      flags=0 
      flags+=RETAIN_FLAG if hash[:retain]
      if qos==-1
        flags+=QOSM1_FLAG
      else
        flags+=QOS1_FLAG*qos 
      end
      p=[PUBLISH_TYPE,flags,hash[:topic_id] >>8 ,hash[:topic_id] & 0xff,@@msg_id >>8 ,@@msg_id & 0xff]
      hash[:msg].each_byte do |b|
        p<<b
      end
      @@msg_id+=1
    when :pubrel 
      raise "Need the original :msg_id of the Publish for PubRel!" if not hash[:msg_id]
      p=[PUBREL_TYPE,hash[:msg_id] >>8 ,hash[:msg_id] & 0xff]
    when :ping
      p=[PINGREQ_TYPE]
    when :disconnect
      if hash[:duration]
        p=[DISCONNECT_TYPE,hash[:duration] >>8 ,hash[:duration] & 0xff]
      else
        p=[DISCONNECT_TYPE]
      end
    else
      puts "Error: Strange send?? #{type}"
      return nil
    end
    if hash[:expect] 
      while not @iq.empty?
        mp=@iq.pop
        puts "WARN:#{@id} ************** Purged message: #{mp}"
      end
      @iq.clear
    end
    raw=send_packet p
    hash[:raw]=raw if @debug
    puts "send:#{@id} #{type},#{hash.to_json}"
    timeout=hash[:timeout]||Tretry
    status=:timeout
    retries=0
    m={}
    if hash[:expect] 
      while retries<Nretry do
        stime=Time.now.to_i
        while Time.now.to_i<stime+timeout
          if not @iq.empty?
            m=@iq.pop
            if Array(hash[:expect]).include? m[:type]
              status=:ok
              break
            else
              puts "WARN:#{@id} ************** Discarded message: #{m}"
            end
          end
          sleep 0.1
        end
        if status==:ok
          break
        else
          retries+=1
          send_packet p
          puts "fail to get ack, retry #{retries} :#{@id} #{type},#{hash.to_json}"
          #need to set DUP flag !
        end
      end

      if block
        block.call  status,m
      end
    end
  end

  def will_and_testament topic,msg
    if @state==:connected #if already connected, send changes, otherwise wait until connect does it.
      if @will_topic!=topic
        send :will_topic_upd, topic: topic, expect: :will_topic_resp do |status,message|
          puts "will topic updated"
          if status==:ok
          else
            puts "Error:#{@id} no pong!"
          end
        end
      end
      if @will_msg!=msg
        send :will_msg_upd, msg: msg, expect: :will_msg_resp do |status,message|
          puts "will msg updated"
          if status==:ok
          else
            puts "Error:#{@id} no pong!"
          end
        end
      end
    end
    @will_topic=topic
    @will_msg=msg
  end

  def connect id
    send :connect,id: id, clean: true, expect: [:connect_ack,:will_topic_req] do |s,m| #add will here!
      if s==:ok
        if m[:type]==:will_topic_req
          puts "will topic!"
          send :will_topic, topic: @will_topic, expect: [:will_msg_req] do |s,m| #add will here!
            if s==:ok
              puts "will msg!"
              send :will_msg, msg: @will_msg, expect: [:connect_ack] do |s,m| 
              end
            end
          end
        end
      end
    end
  end

  def disconnect 
    send :disconnect, expect: :disconnect do |status,message|
    end
  end

  def goto_sleep duration 
    send :disconnect, duration: duration, expect: :disconnect do |status,message|
    end
  end

  def subscribe topic,hash={}
    send :subscribe, topic: topic, qos: hash[:qos],expect: :sub_ack do |status,message|
    end
  end

  def ping
    send :ping, timeout: 2,expect: :pong do |status,message|
      if status==:ok
      else
        puts "Error:#{@id} no pong!"
      end
    end
  end

  def register_topic topic
    send :register,topic: topic, expect: :register_ack do |s,m|
      if s==:ok
        @topics[topic]=m[:topic_id]
      else
        raise "Error:#{@id} Register topic #{topic} failed!"
      end
      pp @topics
    end
    @topics[topic]
  end

  def publish topic,msg,hash={}
    if not @topics[topic]
      register_topic topic
    end
    case hash[:qos]
    when 1
      send :publish,msg: msg, retain: hash[:retain], topic_id: @topics[topic], qos: 1, expect: [:publish_ack] do |s,m|
        if s==:ok
          puts "got handshaken once! status=#{s}, message=#{m.to_json}"
        end
      end
    when 2
      send :publish,msg: msg, retain: hash[:retain], topic_id: @topics[topic], qos: 2, expect: [:pubrec] do |s,m|
        if s==:ok
          if m[:type]==:pubrec
            send :pubrel,msg_id: m[:msg_id], expect: :pubcomp do |s,m|
              puts "got handshaken twice!  status=#{s}, message=#{m.to_json}"
            end
          end
        end
      end
    else
      send :publish,msg: msg, retain: hash[:retain],topic_id: @topics[topic], qos: 0
    end
  end

  def recv_thread
    while true do
      begin 
        r,stuff=@s.recvfrom(200) #_nonblock(200)
        m=nil
        len=r[0].ord
        case r[len-1].ord
        when 0x00
          status=:ok
        when 0x01
          status=:rejected_congestion
        when 0x02
          status=:rejected_invalid_topic_id
        when 0x03
          status=:rejected_not_supported
        else
          status=:unknown_error
        end
        type_byte=r[1].ord
        done=false
        case type_byte
        when CONNACK_TYPE
          m={type: :connect_ack,status: status}
          @state=:connected

        when SUBACK_TYPE
          topic_id=(r[3].ord<<8)+r[4].ord
          msg_id=(r[5].ord<<8)+r[6].ord
          m={type: :sub_ack, topic_id: topic_id, msg_id: msg_id, status: status}
        when PUBLISH_TYPE
          topic_id=(r[3].ord<<8)+r[4].ord
          msg_id=(r[5].ord<<8)+r[6].ord
          msg=r[7,len-7]
          flags=r[2].ord
          qos=(flags>>5)&0x03
          m={type: :publish, qos: qos, topic_id: topic_id, msg_id: msg_id, msg: msg,status: :ok}
          done=true
          if qos==1 #send ack
            send :publish_ack,topic_id: topic_id, msg_id: msg_id, return_code: 0
          elsif qos==2 #send ack
            send :pub_rec, msg_id: msg_id
          end
        when PUBREL_TYPE
          msg_id=(r[2].ord<<8)+r[3].ord
          send :pub_comp, msg_id: msg_id
          done=true
        when DISCONNECT_TYPE
          m={type: :disconnect,status: :ok}
          @state=:disconnected
        when REGISTER_TYPE
          puts "registering... *************************"
          topic_id=(r[2].ord<<8)+r[3].ord
          msg_id=(r[4].ord<<8)+r[5].ord
          topic=r[6,len-6]
          m={type: :register, topic_id: topic_id, msg_id: msg_id, topic: topic,status: :ok}
          @topics[topic]=m[:topic_id]
          pp @topics
          send :register_ack,topic_id: topic_id, msg_id: msg_id, return_code: 0
          done=true
        when REGACK_TYPE
          topic_id=(r[2].ord<<8)+r[3].ord
          m={type: :register_ack,topic_id: topic_id,status: status}
          #@state=:registered
        when PUBREC_TYPE
          msg_id=(r[2].ord<<8)+r[3].ord
          m={type: :pubrec,msg_id: msg_id,status: :ok}
        when PUBACK_TYPE
          topic_id=(r[2].ord<<8)+r[3].ord
          msg_id=(r[4].ord<<8)+r[5].ord
          m={type: :publish_ack,topic_id: topic_id,msg_id: msg_id, status: status}
        when PUBCOMP_TYPE
          msg_id=(r[2].ord<<8)+r[3].ord
          m={type: :pubcomp,status: :ok, msg_id: msg_id}

        when WILLTOPICREQ_TYPE
          m={type: :will_topic_req, status: :ok}
        when WILLMSGREQ_TYPE
          m={type: :will_msg_req, status: :ok}

        when WILLTOPICRESP_TYPE
          m={type: :will_topic_resp, status: :ok}
        when WILLMSGRESP_TYPE
          m={type: :will_msg_resp, status: :ok}

        when PINGRESP_TYPE
          m={type: :pong, status: :ok}
        else
          m={type: :unknown, type_byte: type_byte }
        end
        if @debug
          m[:raw]=hexdump r
        end
        puts "got :#{@id} #{m.to_json}"
        if m[:type]==:publish
          puts "**************************** PUBLISH"
        end
        if not done
          @iq<<m if m
        end
      rescue IO::WaitReadable
        IO.select([@s])
        retry
      rescue => e
        puts "Error: receive thread died: #{e}"
        pp e.backtrace
      end
    end
  end
end