#!/usr/bin/env ruby
# encode: UTF-8

require "pp"
require 'socket'
require 'json'
require 'uri'
require 'ipaddr'
require 'time'


class MqttSN

  Nretry = 3  # Max retry
  Tretry = 3 # Timeout before retry 

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
  TOPIC_PREDEFINED_FLAG =0x01
  TOPIC_SHORT_FLAG =0x02


  def logger str,*args
    if @verbose or @debug
      s=sprintf(str,*args)
      if not @forwarder
        @log_q << sprintf("%s: (%3.3s) | %s",Time.now.iso8601,@active_gw_id,s)
      else
        @log_q << sprintf("%s: [%3.3s] | %s",Time.now.iso8601,@options[:gw_id],s)
      end
     end
  end

  def note str,*args
    s=sprintf(str,*args)
    @log_q << sprintf("%s: %s",Time.now.iso8601,s)
  end

  def log_empty?
    @log_q.empty? or not @verbose
  end

  def log_flush
    while not log_empty?
      sleep 0.1
    end
  end

  def log_thread 
    while true do
      begin
        if not @log_q.empty?
          l=@log_q.pop
          puts l
        else
          sleep 0.01
        end
      rescue => e
        puts "Error: receive thread died: #{e}"
        pp e.backtrace
      end
    end
  end

  def self.open_port uri_s
    begin
      uri = URI.parse(uri_s)
     if uri.scheme== 'udp'
        return [UDPSocket.new,uri.host,uri.port]
      else
        raise "Error: Cannot open socket for '#{uri_s}', unsupported scheme: '#{uri.scheme}'"
      end
    rescue => e
        pp e.backtrace
        raise "Error: Cannot open socket for '#{uri_s}': #{e}"
    end
  end

  def open_multicast_send_port 
    uri = URI.parse(@broadcast_uri)
      
    ip =  IPAddr.new(uri.host).hton + IPAddr.new("0.0.0.0").hton
    socket_b = UDPSocket.new
    socket_b.setsockopt(Socket::IPPROTO_IP, Socket::IP_TTL, [1].pack('i'))
    socket_b
  end

  def open_multicast_recv_port  
    uri = URI.parse(@broadcast_uri)
    ip =  IPAddr.new(uri.host).hton + IPAddr.new("0.0.0.0").hton
    s = UDPSocket.new
    s.setsockopt(Socket::IPPROTO_IP, Socket::IP_ADD_MEMBERSHIP, ip)
    s.setsockopt(:SOL_SOCKET, :SO_REUSEPORT, 1)
    s.bind(Socket::INADDR_ANY, uri.port)
    s
  end

  attr_accessor :clients
  attr_accessor :gateways

  def initialize(hash={})
      @options=hash #save these
      @server_uri=hash[:server_uri]
      @debug=hash[:debug]
      @verbose=hash[:verbose]
      @state=:inited
      @bcast_port=5000
      @keepalive=(hash[:keepalive]||25).to_i
      @forwarder=hash[:forwarder] #flag to indicate forward mode 
      @will_topic=nil
      @will_msg=nil
      @active_gw_id=nil

      @sem=Mutex.new 
      @gsem=Mutex.new 
      @log_q = Queue.new #log queue :) 
      @msg_id=1
      @clients={}
      @gateways={}
      @autodiscovery=false
      @broadcast_uri=hash[:broadcast_uri]

      if @server_uri
        note "Using Default Gateway: #{@server_uri}"
        @gateways[0]={stamp: Time.now.to_i,uri: @server_uri, duration: 0, source: 'default', status: :ok}
        pick_new_gateway 
      elsif @broadcast_uri
        note "Autodiscovery Active, using #{@broadcast_uri}"
        @autodiscovery=true
      else
        note "No autodiscovery and no Default Gateway -- cannot proceed"
        exit -1
      end


      @log_t=Thread.new do
        log_thread
      end

      @topics={} #hash of registered topics is stored here
      @iq = Queue.new
      @dataq = Queue.new
      
      if @broadcast_uri
        @bcast_s=open_multicast_send_port
        @bcast=open_multicast_recv_port 

        @roam_t=Thread.new do
          roam_thread @bcast
        end
      end
      if @forwarder
        @s,@server,@port = MqttSN::open_port @server_uri
        note "Open port to Gateway: #{@server_uri}: #{@server},#{@port} -- Listening local port: #{@local_port}"
        @local_port=hash[:local_port]||1883
        @s.bind("0.0.0.0",@local_port)
        @bcast_period=60
      else
        client_thread 
      end
  end

  def forwarder_thread
    if not @forwarder 
      raise "Cannot Forward if no Forwarder!"
    end
    begin 
      last_kill=0
      stime=Time.now.to_i
      Thread.new do #maintenance
        while true do 
          sleep 1
          changes=false
          @clients.dup.each do |key,data|
            if data[:state]==:disconnected
              dest="#{data[:ip]}:#{data[:port]}"
              note "- %s",dest
              @clients.delete key
              changes=true
            end
          end
          if changes
             note "cli:#{@clients.to_json}"
          end
        end
      end
      while true
        pac=MqttSN::poll_packet_block(@s) #data from clients to our service sovket
        r,client_ip,client_port=pac
        key="#{client_ip}:#{client_port}"
        if not @clients[key]
          uri="udp://#{client_ip}:#{client_port}"
          @clients[key]={ip:client_ip, port:client_port, socket: UDPSocket.new, uri: uri, state: :active  }
          c=@clients[key]
          puts "thread start for #{key}"
          @clients[key][:thread]=Thread.new(key) do |my_key|
            while true
              pacc=MqttSN::poll_packet_block(@clients[my_key][:socket]) #if we get data from server destined to our client
              rr,client_ip,client_port=pacc
              @s.send(rr, 0, @clients[my_key][:ip], @clients[my_key][:port]) # send_packet to client
              mm=MqttSN::parse_message rr
              _,port,_,_ = @clients[my_key][:socket].addr
              dest="#{@server}:#{port}"
              logger "sc %-24.24s <- %-24.24s | %s",@clients[my_key][:uri],@gateways[@active_gw_id][:uri],mm.to_json
              case mm[:type]
              when :disconnect
                @clients[my_key][:state]=:disconnected
              end
            end
          end
          dest="#{client_ip}:#{client_port}"
          note "+ %s\n",dest
          note "cli: #{@clients.to_json}"
        end
        @clients[key][:stamp]=Time.now.to_i
        m=MqttSN::parse_message r
        case m[:type]
        when :publish
          if m[:qos]==-1
            @clients[key][:state]=:disconnected #one shot
          end
        end
        sbytes=@clients[key][:socket].send(r, 0, @server, @port) # to rsmb -- ok as is
        _,port,_,_ = @clients[key][:socket].addr
        dest="#{@server}:#{port}"
        if @active_gw_id
          logger "cs %-24.24s -> %-24.24s | %s", @clients[key][:uri],@gateways[@active_gw_id][:uri],m.to_json
        else
          logger "cs %-24.24s -> %-24.24s | %s", @clients[key][:uri],"??",m.to_json
        end
       end
    end
  end

  def kill_clients
    puts "Killing Clients:"
    @clients.each do |key,c|
      puts "Killing #{key}"
      send_packet [DISCONNECT_TYPE],@s,c[:ip], c[:port]
      send_packet [DISCONNECT_TYPE],c[:socket], @server,@port
    end
    puts "Killing Clients Done."
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
    if @state!=:connected and type!=:connect and type!=:will_topic  and type!=:will_msg  and type!=:searchgw 
      if type==:disconnect
        return #already disconnected.. nothing to do
      elsif type==:publish and hash[:qos]==-1
      else
        note "Error: Cannot #{type} while unconnected, send :connect first!"
        return nil
      end
    end
    case type
    when :connect
      if not hash[:id] or hash[:id]=""
        hash[:id]="mqtt-sn-ruby-#{$$}"
      end
      note "Connecting as '#{hash[:id]}'"
      flags=0 
      flags+=CLEAN_FLAG if hash[:clean]
      flags+=RETAIN_FLAG if hash[:retain]
      flags+=WILL_FLAG if @will_topic
      p=[CONNECT_TYPE,flags,0x01,hash[:duration]>>8 ,hash[:duration] & 0xff]
      hash[:id].each_byte do |b|
        p<<b
      end
      @id=hash[:id]
    when :register 
      raise "Need :topic to Publish!" if not hash[:topic]
      p=[REGISTER_TYPE,0,0,@msg_id >>8 ,@msg_id & 0xff]
      hash[:topic].each_byte do |b|
        p<<b
      end
      @msg_id+=1
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
      p=[SUBSCRIBE_TYPE,flags,@msg_id >>8 ,@msg_id & 0xff]
      hash[:topic].each_byte do |b|
        p<<b
      end
      @msg_id+=1

    when :unsubscribe 
      raise "Need :topic to :unsubscribe" if not hash[:topic]
      p=[UNSUBSCRIBE_TYPE,0,@msg_id >>8 ,@msg_id & 0xff]
      hash[:topic].each_byte do |b|
        p<<b
      end
      @msg_id+=1

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
      if hash[:topic_type]==:short
        flags+=TOPIC_SHORT_FLAG
      elsif hash[:topic_type]==:predefined
        flags+=TOPIC_PREDEFINED_FLAG
      end
      p=[PUBLISH_TYPE,flags,hash[:topic_id] >>8 ,hash[:topic_id] & 0xff,@msg_id >>8 ,@msg_id & 0xff]
      hash[:msg].each_byte do |b|
        p<<b
      end
      @msg_id+=1
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
    if not hash[:expect]
      if type==:searchgw
        raw=send_packet_bcast p
      else
        raw=send_packet_gw p
      end
      return
    end
    @sem.synchronize do #one command at a time -- 
      if hash[:expect]
        while not @iq.empty?
          mp=@iq.pop
          puts "WARN:#{@id} ************** Purged message: #{mp}"
        end
        @iq.clear
      end
      if type==:searchgw
        raw=send_packet_bcast p
      else
        raw=send_packet_gw p
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
            send_packet_gw p
            puts "fail to get ack, retry #{retries} :#{@id} #{type},#{hash.to_json}"
            #need to set DUP flag !
          end
        end
        if status==:timeout
          note "Warn: ack timeouted, assume disconnected"
          @state=:disconnect
          gateway_close :timeout
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

  def send_packet m,socket,server,port
    msg=MqttSN::build_packet m
    MqttSN::send_raw_packet msg,socket,server,port
    dest="#{server}:#{port}"
     _,port,_,_ = socket.addr
    src=":#{port}"
    logger "od %-18.18s <- %-18.18s | %s",dest,src,MqttSN::parse_message(msg).to_json
  end

  def send_packet_bcast m
    uri = URI.parse(@broadcast_uri)
    msg=MqttSN::build_packet m
    MqttSN::send_raw_packet msg,@bcast_s,uri.host,uri.port
     _,port,_,_ = @bcast_s.addr
    src="udp://0.0.0.0:#{port}"
    logger "ob %-24.24s <- %-24.24s | %s",@broadcast_uri,src,MqttSN::parse_message(msg).to_json
  end

  def send_packet_gw m
    msg=MqttSN::build_packet m
    waits=0
    debug={}
    debug[:debug]=MqttSN::hexdump(msg) if @debug

    if not @active_gw_id or not @gateways[@active_gw_id] or not @gateways[@active_gw_id][:socket] 
      note "No active gw, wait ."
      while not @active_gw_id or not @gateways[@active_gw_id] or not @gateways[@active_gw_id][:socket] 
        ret="-"
        if  not ret=pick_new_gateway
          sleep 0.5
          #print "."
        end
        waits+=1
        if waits>30
          puts "\nNone Found -- not sending"
          return
        end
      end
      note "Gw Ok!"  
    end  

    if @active_gw_id and @gateways[@active_gw_id] and @gateways[@active_gw_id][:socket] 
      #get server & port from uri!
      uri=URI.parse(@gateways[@active_gw_id][:uri])
      #uri.scheme
      MqttSN::send_raw_packet msg,@gateways[@active_gw_id][:socket],uri.host,uri.port
      _,port,_,_ = @gateways[@active_gw_id][:socket].addr
      src="udp://0.0.0.0:#{port}"
      logger "od %-24.24s <- %-24.24s | %s",@gateways[@active_gw_id][:uri],src,MqttSN::parse_message(msg).merge(debug).to_json
    else
      puts "no gw to send.."
      sleep 1
    end
  end

  def self.poll_packet socket
    #decide how to get data -- UDP-socket or FM-radio
    begin
      r,stuff=socket.recvfrom_nonblock(200) #get_packet --high level func!
      client_ip=stuff[2]
      client_port=stuff[1]
      return [r,client_ip,client_port]
    rescue IO::WaitReadable
      sleep 0.1
    rescue => e
      puts "Error: receive thread died: #{e}"
      pp e.backtrace
    end
    return nil
  end

  def self.poll_packet_block socket
    #decide how to get data -- UDP-socket or FM-radio
    r,stuff=socket.recvfrom(200) #get_packet --high level func!
    client_ip=stuff[2]
    client_port=stuff[1]
    return [r,client_ip,client_port]
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

  def connect id,&block
    send :connect,id: id, clean: false, duration: @keepalive, expect: [:connect_ack,:will_topic_req] do |s,m| #add will here!
      if s==:ok
        if m[:type]==:will_topic_req
          send :will_topic, topic: @will_topic, expect: [:will_msg_req] do |s,m| #add will here!
            if s==:ok
              send :will_msg, msg: @will_msg, expect: [:connect_ack] do |s,m| 
              end
            end
          end
        elsif m[:type]==:connect_ack
          block.call :ok,m if block
        end
      else
        block.call :fail,m if block
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

  ##
  # Mid-level function to send Subscription to Broker, if code block is provided, it will run the block when new messages are received.
  # When subsciption is established with Broker, a :sub_ack message is given to code block.
  # Incoming messages are indicated with :got_data status.
  # If connection to Broker is disrupted, a :disconnect message is given.!
  
  def subscribe topic,hash={},&block  # :yields: status, message
    send :subscribe, topic: topic, qos: hash[:qos],expect: :sub_ack do |s,m|
      if s==:ok
        if m[:topic_id] and m[:topic_id]>0 #when subs topic has no wild cards, we get topic id here:
          if m[:topic_type]==:long
            @topics[topic]=m[:topic_id]
          end
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
            #gateway_close :subscribe_disconnected
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
    if topic[0]=="="
      topic[0]=""
      topic_id=topic.to_i
      topic_type=:predefined
    elsif topic.size==2
      topic_id=((topic[0].ord&0xff)<<8)+(topic[1].ord&0xff)
      topic_type=:short
    else
      topic_type=:long
      if not @topics[topic]
        register_topic topic
      end
      topic_id=@topics[topic]
    end
    case hash[:qos]
    when 1
      send :publish,msg: msg, retain: hash[:retain], topic_id: topic_id, topic_type: topic_type, qos: 1, expect: [:publish_ack] do |s,m|
        if s==:ok
        end
      end
    when 2
      send :publish,msg: msg, retain: hash[:retain], topic_id: topic_id, topic_type: topic_type, qos: 2, expect: [:pubrec] do |s,m|
        if s==:ok
          if m[:type]==:pubrec
            send :pubrel,msg_id: m[:msg_id], expect: :pubcomp do |s,m|
            end
          end
        end
      end
    else
      send :publish,msg: msg, retain: hash[:retain],topic_id: topic_id, topic_type: topic_type, qos: hash[:qos]||0
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
      msg_id=(r[3].ord<<8)+r[4].ord
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
      topic_type=:long
      topic=""
      if flags&0x03==TOPIC_SHORT_FLAG
        topic_type=:short
        topic=r[3].chr+r[4].chr
      elsif flags&0x03==TOPIC_PREDEFINED_FLAG
        topic_type=:predefined
        topic=""
      end
      qos=(flags>>5)&0x03
      qos=-1 if qos==3
      m={type: :publish, qos: qos, topic_id: topic_id, topic_type:topic_type, topic: topic, msg_id: msg_id, msg: msg,status: :ok}
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

    when PINGREQ_TYPE
      m={type: :ping, status: :ok}
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
      if m[:topic_type]==:long
        m[:topic]=@topics.key(m[:topic_id])
      end
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

  def client_thread 
    Thread.new do #ping thread
      while true do
        begin
          while @state!=:connected 
            sleep 1
          end
          sleep @keepalive
          if @active_gw_id and @gateways[@active_gw_id] and @gateways[@active_gw_id][:socket] #if we are connected...
            send :ping, timeout: 2,expect: :pong do |status,message|
              if status!=:ok
                note "Error:#{@id} no pong! -- sending disconnect to app"
                @state=:disconnected
                gateway_close :timeout
              end
            end
          end
        rescue => e
          puts "Error: receive thread died: #{e}"
          pp e.backtrace
        end
      end
    end

    Thread.new do #work thread
      while true do
        begin
          if @active_gw_id and @gateways[@active_gw_id] and @gateways[@active_gw_id][:socket] #if we are connected...
            if pac=MqttSN::poll_packet(@gateways[@active_gw_id][:socket]) #cannot block -- gateway may change...
              r,client_ip,client_port=pac 
              m=MqttSN::parse_message r
              if @debug and m
                m[:debug]=MqttSN::hexdump r
              end
              _,port,_,_= @gateways[@active_gw_id][:socket].addr
              src="udp://0.0.0.0:#{port}"
              logger "id %-24.24s -> %-24.24s | %s",@gateways[@active_gw_id][:uri],src,m.to_json
              process_message m
            else
              sleep 0.01
            end
          else
            sleep 0.01
          end
        rescue => e
          puts "Error: receive thread died: #{e}"
          pp e.backtrace
        end
      end
    end
  end

  def process_broadcast_message m,client_ip,client_port
    case m[:type]
    when :searchgw
      if @forwarder
        _,port,_,_=@bcast.addr
        #logger "ib %-24.24s -> %-24.24s | %s","udp://0.0.0.0:#{port}",@broadcast_uri,m.to_json
        send_packet_bcast [GWINFO_TYPE,@options[:gw_id]]
      end
    when :advertise,:gwinfo
      gw_id=m[:gw_id]  
      duration=m[:duration]||180
      uri="udp://#{client_ip}:1882"
      if not @gateways[gw_id]
         @gateways[gw_id]={stamp: Time.now.to_i,uri: uri, duration: duration, source: m[:type], status: :ok, last_use: 0}
      else
        if @gateways[gw_id][:uri]!=uri
          note "conflict -- gateway has moved? or duplicate"
        else
          @gateways[gw_id][:stamp]=Time.now.to_i
          @gateways[gw_id][:duration]=duration 
          @gateways[gw_id][:source]=m[:type] 
        end
      end
    end
  end


  def gateway_close cause
    @gsem.synchronize do #one command at a time -- 
    
      if @active_gw_id # if using one, mark it used, so it will be last reused
        note "Closing gw #{@active_gw_id} cause: #{cause}"
        @gateways[@active_gw_id][:last_use]=Time.now.to_i
        if @gateways[@active_gw_id][:socket]
          @gateways[@active_gw_id][:socket].close
          @gateways[@active_gw_id][:socket]=nil
        end
        @active_gw_id=nil
      end
    end     
  end

  def pick_new_gateway 
    begin
      gateway_close nil
      @gsem.synchronize do #one command at a time -- 
        pick=nil
        pick_t=0
        @gateways.each do |gw_id,data|
          if data[:uri] and data[:status]==:ok
            if not pick or data[:last_use]==0  or pick_t>data[:last_use]
              pick=gw_id
              pick_t=data[:last_use]
            end
          end
        end
        if pick
          @active_gw_id=pick
          note "Opening Gateway #{@active_gw_id}: #{@gateways[@active_gw_id][:uri]}"
          @s,@server,@port = MqttSN::open_port @gateways[@active_gw_id][:uri]
          @gateways[@active_gw_id][:socket]=@s
          @gateways[@active_gw_id][:last_use]=Time.now.to_i
        else
          #note "Error: no usable gw found !!"
        end
      end
    rescue => e
      puts "Error: receive thread died: #{e}"
      pp e.backtrace
    end
    return @active_gw_id
  end

  def roam_thread socket
    @last_bcast=0
    if @forwarder
      Thread.new do
        while true do
          send_packet_bcast [ADVERTISE_TYPE,@options[:gw_id],@bcast_period>>8,@bcast_period&0xff]
          sleep @bcast_period
        end
      end
    elsif @autodiscovery  #client should try to find some gateways..
      Thread.new do
        while true do
          send :searchgw #replies may or may not come -- even multiple!
          if @gateways=={}
            sleep 5
          else
            #pp @gateways
            sleep 30
          end
        end
      end
      Thread.new do
        while true do
          if @active_gw_id and @gateways[@active_gw_id] and @gateways[@active_gw_id][:socket]
          else # not so ok -- pick one!
            #pick_new_gateway 
          end
          sleep 0.01
        end
      end
    end
    while true do
      begin
        if @bcast 
         pac=MqttSN::poll_packet_block(socket)
          r,client_ip,client_port=pac 
          m=MqttSN::parse_message r
          if @debug and m
            m[:debug]=MqttSN::hexdump r
          end
          _,port,_,_ = @bcast.addr
          src="udp://#{client_ip}:#{client_port}"
          logger "ib %-24.24s <- %-24.24s | %s",@broadcast_uri,src,m.to_json
          process_broadcast_message m,client_ip,client_port
        end
      rescue => e
        puts "Error: receive thread died: #{e}"
        pp e.backtrace
      end
    end
  end


#toplevel funcs:
  def pub options={}
    sent=false
    if options[:qos]==-1
      publish options[:topic]||"XX", options[:msg]||"test_value", qos: options[:qos]
      puts "Sent."
    else
      while not sent
        connect options[:id] do |s,m|
          if s==:ok
            publish options[:topic]||"test/message/123", options[:msg]||"test_value", qos: options[:qos]
            puts "Sent ok."
            sent=true
          else
            disconnect
          end
        end
      end
    end
    log_flush 
  end

  def sub options={},&block
    loop do
      note "Connecting.."
      connect options[:id] do |cs,cm|
        note "connect result: #{cs} #{cm}"
        if cs==:ok 
          note "Subscribing.."
          subscribe options[:topic]||"test/message/123", qos: options[:qos] do |s,m|
            if s==:sub_ack
              note "Subscribed Ok! Waiting for Messages!"
            elsif s==:disconnect
              note "Disconnected -- switch to new gateway"
            else
             if block
                block.call s,m
              else
                note "Got Message: #{s}: #{m}"
              end
            end
          end
        end
      end
      puts "Disconnected..."
    end
end


end