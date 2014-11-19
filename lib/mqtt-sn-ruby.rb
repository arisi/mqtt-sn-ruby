#!/usr/bin/env ruby
# encode: UTF-8

require "pp"
require 'logger'
require 'socket'
require 'json'
require 'uri'
require 'ipaddr'


class MqttSN

  Nretry = 5  # Max retry
  Tretry = 10 # Timeout before retry 
  
  MULTICAST_ADDR = "225.4.5.6" 

  SEARCHGW_TYPE  =0x01
  GWINFO_TYPE    =0x02
  ADVERTISE_TYPE =0x03
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
  @@clients={}
  @@gateways={}
  @@log_q = Queue.new #log queue :) 
  @@log_t=Thread.new do
    log_thread
  end

  def self.logger str,*args
    @@log_q << sprintf(str,*args)
  end
  
  def self.open_port uri_s
    begin
      uri = URI.parse(uri_s)
      pp uri
      if uri.scheme== 'udp'
        puts "server: #{@server}:#{@port}"
        return [UDPSocket.new,uri.host,uri.port]
      else
        raise "Error: Cannot open socket for '#{uri_s}', unsupported scheme: '#{uri.scheme}'"
      end
    rescue => e
        pp e.backtrace
        raise "Error: Cannot open socket for '#{uri_s}': #{e}"
    end
  end

  def self.open_multicast_send_port port
    ip =  IPAddr.new(MULTICAST_ADDR).hton + IPAddr.new("0.0.0.0").hton
    socket_b = UDPSocket.new
    socket_b.setsockopt(Socket::IPPROTO_IP, Socket::IP_TTL, [1].pack('i'))
    socket_b
  end

  def self.open_multicast_recv_port port 
    ip =  IPAddr.new(MULTICAST_ADDR).hton + IPAddr.new("0.0.0.0").hton
    s = UDPSocket.new
    s.setsockopt(Socket::IPPROTO_IP, Socket::IP_ADD_MEMBERSHIP, ip)
    s.setsockopt(:SOL_SOCKET, :SO_REUSEPORT, 1)
    s.bind(Socket::INADDR_ANY, port)
    s
  end

  def initialize(hash={})
      @options=hash #save these
      @server_uri=hash[:server_uri]||"udp://localhost:1883"
      @debug=hash[:debug]
      @verbose=hash[:verbose]
      @state=:inited
      @bcast_port=5000
      @forward=hash[:forward] #flag to indicate forward mode 
      @will_topic=nil
      @will_msg=nil
      @id="?"
      @sem=Mutex.new 
      @topics={} #hash of registered topics is stored here
      @iq = Queue.new
      @dataq = Queue.new
      @s,@server,@port = MqttSN::open_port @server_uri

      @bcast_s=MqttSN::open_multicast_send_port @bcast_port
      @bcast=MqttSN::open_multicast_recv_port @bcast_port

      @roam_t=Thread.new do
        roam_thread @bcast
      end
      if not @options[:forwarder]
        @client_t=Thread.new do
          client_thread @s
        end
      else
        @s.bind("0.0.0.0",hash[:local_port]||1883)
        @bcast_period=60
        loop do      
          forwarder
        end
      end
 
  end


  def forwarder 
    begin 
      last_bcast=0
      last_kill=0
      stime=Time.now.to_i
      while true
        now=Time.now.to_i
        if now>last_bcast+@bcast_period
           #periodically broadcast :advertize
          MqttSN::send_packet [ADVERTISE_TYPE,0xAB,0,30],@bcast_s,MULTICAST_ADDR,@bcast_port
          last_bcast=now
        end
        #periodically kill disconnected clients -- and those timed out..
        if now>last_kill+1
          changes=false
          @@clients.dup.each do |key,data|
            if data[:state]==:disconnected
              dest="#{data[:ip]}:#{data[:port]}"
              MqttSN::logger "- %s",dest
              @@clients.delete key
              changes=true
            end
          end
          if changes
             MqttSN::logger "cli:#{@@clients.to_json}"
          end
          last_kill=now
        end
       
        if false # pac=MqttSN::poll_packet(@bcast)
          r,client_ip,client_port=pac
          key="#{client_ip}:#{client_port}"
          dest="#{MULTICAST_ADDR};#{@bcast_port}"
          m=MqttSN::parse_message r
          MqttSN::logger "R %-18.18s -> %-18.18s | %s",key,dest,m.to_json

          case m[:type]
          when :searchgw
            dest="#{client_ip}:#{client_port}"
            MqttSN::logger "C %-18.18s -> %-18.18s | %s",key,dest,m.to_json
            MqttSN::send_packet [GWINFO_TYPE,0xAB],@bcast_s,MULTICAST_ADDR,@bcast_port
            done=true
          end

        end
        if pac=MqttSN::poll_packet(@s)
          r,client_ip,client_port=pac
          key="#{client_ip}:#{client_port}"
          if not @@clients[key]
            @@clients[key]={ip:client_ip, port:client_port, socket: UDPSocket.new, state: :active  }
            dest="#{client_ip}:#{client_port}"
            MqttSN::logger "+ %s\n",dest
            MqttSN::logger "cli: #{@@clients.to_json}"
          end
          @@clients[key][:stamp]=Time.now.to_i
          m=MqttSN::parse_message r
          done=false
          
          if not done # not done locally -> forward it
            sbytes=@@clients[key][:socket].send(r, 0, @server, @port) # to rsmb -- ok as is
            _,port,_,_ = @@clients[key][:socket].addr
            dest="#{@server}:#{port}"
            MqttSN::logger "C %-18.18s -> %-18.18s | %s",key,dest,m.to_json
          end
        end
        @@clients.each do |key,c|
          if pac=MqttSN::poll_packet(c[:socket])
            r,client_ip,client_port=pac
            #puts "got packet #{pac} from server to client #{key}:"
            #puts "sending to #{c[:ip]}:#{c[:port]}"
            @s.send(r, 0, c[:ip], c[:port]) # send_packet
            m=MqttSN::parse_message r
            _,port,_,_ = @@clients[key][:socket].addr
            dest="#{@server}:#{port}"
            MqttSN::logger "S %-18.18s <- %-18.18s | %s",key,dest,m.to_json
            case m[:type]
            when :disconnect
              @@clients[key][:state]=:disconnected
            end
          end
        end
        sleep 0.01
      end
    end
  end


  def self.hexdump data
    raw=""
    data.each_byte do |b|
      raw=raw+"," if raw!=""
      raw=raw+sprintf("%02X",b)
    end
    raw
  end

  def self.build_packet m
    msg=" "
    len=1
    m.each_with_index do |b,i|
      msg[i+1]=b.chr
      len+=1
    end
    msg[0]=len.chr
    msg
  end

  def send type,hash={},&block
    #puts ""  if @verbose
    if @state!=:connected and type!=:connect and type!=:will_topic  and type!=:will_msg
      if type==:disconnect
        return #already disconnected.. nothing to do
      else
        raise "Error: Cannot #{type} while unconnected, send :connect first!"
      end
    end
    case type
    when :connect
      if not hash[:id]
        hash[:id]="xxx"
      end
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

    when :unsubscribe 
      raise "Need :topic to :unsubscribe" if not hash[:topic]
      p=[UNSUBSCRIBE_TYPE,0,@@msg_id >>8 ,@@msg_id & 0xff]
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
     when :searchgw
      p=[SEARCHGW_TYPE,0]
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
    status=:timeout
    m={}
    @sem.synchronize do #one command at a time -- 
      if hash[:expect]
        while not @iq.empty?
          mp=@iq.pop
          puts "WARN:#{@id} ************** Purged message: #{mp}"
        end
        @iq.clear
      end
      if type==:searchgw
        raw=MqttSN::send_packet p,@bcast,MULTICAST_ADDR,@bcast_port
      else
        raw=MqttSN::send_packet p,@s,@server,@port
      end
      hash[:debug]=raw if @debug
      #puts "send:#{@id} #{type},#{hash.to_json}" if @verbose
      timeout=hash[:timeout]||Tretry
      retries=0
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
      end
    end #sem
    if block
      block.call  status,m
    end

  end

  def self.send_raw_packet msg,socket,server,port
    if socket
      socket.send(msg, 0, server, port)
      MqttSN::hexdump msg
    else
      puts "Error: no socket at send_raw_packet"
    end
  end

  def self.send_packet m,socket,server,port
    msg=MqttSN::build_packet m
    MqttSN::send_raw_packet msg,socket,server,port
    dest="#{server}:#{port}"
     _,port,_,_ = socket.addr
    src=":#{port}"
    MqttSN::logger "< %-18.18s <- %-18.18s | %s",dest,src,parse_message(msg).to_json
  end


  def send_packet m
    MqttSN::send_packet m,@s,@server,@port
  end

  def self.poll_packet socket
    #decide how to get data -- UDP-socket or FM-radio
    begin
      r,stuff=socket.recvfrom_nonblock(200) #get_packet --high level func!
      client_ip=stuff[2]
      client_port=stuff[1]
      return [r,client_ip,client_port]
    rescue IO::WaitReadable
    rescue => e
      puts "Error: receive thread died: #{e}"
      pp e.backtrace
    end
    return nil
  end

  def self.get_clients
    @@clients
  end

  def self.get_gateways
    @@gateways
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
  
  def subscribe topic,hash={},&block
    send :subscribe, topic: topic, qos: hash[:qos],expect: :sub_ack do |s,m|
      if s==:ok
        if m[:topic_id] and m[:topic_id]>0 #when subs topic has no wild cards, we get topic id here:
          @topics[topic]=m[:topic_id]
        end
      end
      if block
        block.call :sub_ack,m
        while true
          if not @dataq.empty?
            m=@dataq.pop
            block.call :got_data,m
          end
          sleep 0.1
          if @state!=:connected
            block.call :disconnect,{}
            break
          end
        end
      end
    end
  end

  def unsubscribe topic
    send :unsubscribe, topic: topic, expect: :unsub_ack do |s,m|
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
      #pp @topics
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
        end
      end
    when 2
      send :publish,msg: msg, retain: hash[:retain], topic_id: @topics[topic], qos: 2, expect: [:pubrec] do |s,m|
        if s==:ok
          if m[:type]==:pubrec
            send :pubrel,msg_id: m[:msg_id], expect: :pubcomp do |s,m|
            end
          end
        end
      end
    else
      send :publish,msg: msg, retain: hash[:retain],topic_id: @topics[topic], qos: 0
    end
  end

  def self.parse_message r
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
    when CONNECT_TYPE
      duration=(r[4].ord<<8)+r[5].ord
      id=r[6,len-6]
      m={type: :connect, flags: r[2].ord, duration: duration, client_id: id, status: :ok}
    when CONNACK_TYPE
      m={type: :connect_ack,status: status}
    when SUBACK_TYPE
      topic_id=(r[3].ord<<8)+r[4].ord
      msg_id=(r[5].ord<<8)+r[6].ord
      m={type: :sub_ack, topic_id: topic_id, msg_id: msg_id, status: status}
    when SUBSCRIBE_TYPE
      msg_id=(r[5].ord<<8)+r[6].ord
      topic=r[5,len-5]
      m={type: :subscribe, flags: r[2].ord, topic: topic, msg_id: msg_id, status: :ok}
    when UNSUBACK_TYPE
      msg_id=(r[2].ord<<8)+r[3].ord
      m={type: :unsub_ack, msg_id: msg_id, status: :ok}
    when PUBLISH_TYPE
      topic_id=(r[3].ord<<8)+r[4].ord
      msg_id=(r[5].ord<<8)+r[6].ord
      msg=r[7,len-7]
      flags=r[2].ord
      qos=(flags>>5)&0x03
      m={type: :publish, qos: qos, topic_id: topic_id,msg_id: msg_id, msg: msg,status: :ok}
    when PUBREL_TYPE
      msg_id=(r[2].ord<<8)+r[3].ord
      m={type: :pub_rel, msg_id: msg_id, status: :ok}
    when DISCONNECT_TYPE
      m={type: :disconnect,status: :ok}
    when REGISTER_TYPE
      topic_id=(r[2].ord<<8)+r[3].ord
      msg_id=(r[4].ord<<8)+r[5].ord
      topic=r[6,len-6]
      m={type: :register, topic_id: topic_id, msg_id: msg_id, topic: topic,status: :ok}
    when REGACK_TYPE
      topic_id=(r[2].ord<<8)+r[3].ord
      m={type: :register_ack,topic_id: topic_id,status: status}
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

    when SEARCHGW_TYPE
      m={type: :searchgw, radius: r[2].ord, status: :ok}
    when GWINFO_TYPE
      m={type: :gwinfo, gw_id: r[2].ord, status: :ok}
    when ADVERTISE_TYPE
      duration=(r[3].ord<<8)+r[4].ord
      m={type: :advertise, gw_id: r[2].ord, duration: duration, status: :ok}

    when PINGRESP_TYPE
      m={type: :pong, status: :ok}

    else
      m={type: :unknown, type_byte: type_byte }
    end
    m
  end

  def process_message m    
    done=false
    case m[:type]
    when :register
      @topics[m[:topic]]=m[:topic_id]
      if not @transfer
        send :register_ack,topic_id: m[:topic_id], msg_id: m[:msg_id], return_code: 0
        done=true
      end
    when :disconnect
      @state=:disconnected if not @transfer
    when :pub_rel
      if not @transfer
        send :pub_comp, msg_id: m[:msg_id]
        done=true
      end
    when :publish
      m[:topic]=@topics.key(m[:topic_id])

      if not @transfer
        @dataq<<m
        if m[:qos]==1 
          send :publish_ack,topic_id: m[:topic_id], msg_id: m[:msg_id], return_code: 0
        elsif m[:qos]==2 
          send :pub_rec, msg_id: m[:msg_id]
        end
        done=true
      end
    when :connect_ack
      @state=:connected
    when :searchgw
      done=true
    when :advertise
      done=true
    when :gwinfo
      done=true
    end
   # puts "got :#{@id} #{m.to_json}"  if @verbose
    if not done
      @iq<<m if m
    end
    m
  end

  def client_thread socket
    while true do
      begin
        if pac=MqttSN::poll_packet(socket)
          r,client_ip,client_port=pac 
          m=MqttSN::parse_message r
          if @debug and m
            m[:debug]=MqttSN::hexdump r
          end
          dest="#{client_ip}:#{client_port}"
          _,port,_,_ = @s.addr
          src=port
          MqttSN::logger "> %-18.18s <- %-18.18s | %s",dest,":#{port}",m.to_json
          process_message m
        end
      rescue => e
        puts "Error: receive thread died: #{e}"
        pp e.backtrace
      end
    end
  end

  def process_broadcast_message m,client_ip,client_port
    case m[:type]
    when :searchgw
      MqttSN::logger "hey, someone is looking for gateway..."
      key="#{client_ip}:#{client_port}"
      dest="#{MULTICAST_ADDR};#{@bcast_port}"
      #actually -- send data on all gateways we know...
      MqttSN::logger "r %-18.18s -> %-18.18s | %s",key,dest,m.to_json
      MqttSN::send_packet [GWINFO_TYPE,0xAB],@bcast_s,MULTICAST_ADDR,@bcast_port
    when :advertise,:gwinfo
      MqttSN::logger "hey, we have gateway there!"
      if not @@gateways[client_ip]
         @@gateways[client_ip]={stamp: Time.now.to_i}
      else
         @@gateways[client_ip][:stamp]=Time.now.to_i
      end
      @@gateways[client_ip][:gw_id]=m[:gw_id]
      @@gateways[client_ip][:duration]=m[:duration]
      MqttSN::logger "gw: #{@@gateways.to_json}"
    end
  end

  def roam_thread socket
    while true do
      begin
        if @bcast 
          if pac=MqttSN::poll_packet(socket)
            r,client_ip,client_port=pac 
            m=MqttSN::parse_message r
            if @debug and m
              m[:debug]=MqttSN::hexdump r
            end
            dest="#{client_ip}:#{client_port}"
            _,port,_,_ = @bcast.addr
            src=port
            MqttSN::logger "R %-18.18s <- %-18.18s | %s",dest,":#{port}",m.to_json
            process_broadcast_message m,client_ip,client_port
          end
        end
      rescue => e
        puts "Error: receive thread died: #{e}"
        pp e.backtrace
      end
    end
  end

  def self.log_thread 
    while true do
      begin
        if not @@log_q.empty?
          l=@@log_q.pop
          puts l
        end
      rescue => e
        puts "Error: receive thread died: #{e}"
        pp e.backtrace
      end
    end
  end

end