#!/usr/bin/env ruby
# encode: UTF-8

require "pp"
require 'socket'
require 'json'



class MqttSN

  CONNECT_TYPE=0x04
  CONNACK_TYPE=0x05
  REGISTER_TYPE=0x0A
  REGACK_TYPE=0x0B
  PUBLISH_TYPE=0x0C
  PUBACK_TYPE =0x0D
  PUBCOMP_TYPE =0x0E
  PUBREC_TYPE =0x0F
  PUBREL_TYPE =0x10
  PINGREQ_TYPE=0x16
  PINGRESP_TYPE=0x17
  DISCONNECT_TYPE=0x18

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
    case type
    when :connect
      flags=0 
      flags+=CLEAN_FLAG if hash[:clean]
      flags+=RETAIN_FLAG if hash[:retain]
      p=[CONNECT_TYPE,flags,0x01,0,30]
      hash[:id].each_byte do |b|
        p<<b
      end
    when :register 
      raise "Need :topic to Publish!" if not hash[:topic]
      p=[REGISTER_TYPE,0,0,@@msg_id >>8 ,@@msg_id & 0xff]
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
      p=[DISCONNECT_TYPE]
    else
      puts "Error: Strange send?? #{type}"
      return nil
    end
    @iq.clear
    stime=Time.now.to_i
    raw=send_packet p
    hash[:raw]=raw if @debug
    puts "send: #{type},#{hash.to_json}"
    timeout=hash[:timeout]||10
    status=:timeout
    m={}
    if hash[:expect] #wait timeout time for reply_type to arrive..
      #puts "waiting for #{hash[:expect]}, timeout: #{timeout}"
      while Time.now.to_i<stime+timeout
        if not @iq.empty?
          m=@iq.pop
          if Array(hash[:expect]).include? m[:type]
            status=:ok
            break
          end
        end
        sleep 0.1
      end
      if block
        block.call  status,m
      end
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
        case type_byte
        when CONNACK_TYPE
          m={type: :connect_ack,status: status}
          @state=:connected
        when DISCONNECT_TYPE
          m={type: :disconnect,status: status}
          @state=:disconnected
        when REGACK_TYPE
          topic_id=(r[2].ord<<8)+r[3].ord
          m={type: :register_ack,topic_id: topic_id,status: status}
          @state=:registered
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
        when PINGRESP_TYPE
          m={type: :pong, status: :ok}
        else
          m={type: :unknown, type_byte: type_byte }
        end
        if @debug
          m[:raw]=hexdump r
        end
        puts "got: #{m.to_json}"
        @iq<<m if m
      rescue IO::WaitReadable
        IO.select([@s])
        retry
      rescue => e
        puts "Error: receive thread died:"
        pp e
      end
    end
  end
end