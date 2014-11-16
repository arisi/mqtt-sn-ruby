#!/usr/bin/env ruby
# encode: UTF-8

require "pp"
require 'socket'
require 'json'

$s = UDPSocket.new


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

RETAIN_FLAG=0x10
WILL_FLAG  =0x08
CLEAN_FLAG =0x04
QOSM1_FLAG =0x60
QOS2_FLAG  =0x40
QOS1_FLAG  =0x20
QOS0_FLAG  =0x00

$msg_id=1
$iq = Queue.new

def send_packet m
  msg=" "
  len=1
  m.each_with_index do |b,i|
    msg[i+1]=b.chr
    len+=1
  end
  msg[0]=len.chr
  if false
    print ">> "
    msg.each_byte do |ch|
      printf "%02X ",ch
    end
    puts ""
  end
  $s.send(msg, 0, '20.20.20.21', 1883)
end

def send type,hash={},&block
  puts ""
  puts "#{type},#{hash.to_json}"
  case type
  when :connect 
    p=[CONNECT_TYPE,CLEAN_FLAG,0x01,0,30]
    hash[:id].each_byte do |b|
      p<<b
    end
  when :register 
    raise "Need :topic to Publish!" if not hash[:topic]
    p=[REGISTER_TYPE,0,0,$msg_id >>8 ,$msg_id & 0xff]
    hash[:topic].each_byte do |b|
      p<<b
    end
    $msg_id+=1
  when :publish
    raise "Need :topic_id to Publish!" if not hash[:topic_id]
    p=[PUBLISH_TYPE,0x20*(hash[:qos]||0),hash[:topic_id] >>8 ,hash[:topic_id] & 0xff,$msg_id >>8 ,$msg_id & 0xff]
    hash[:msg].each_byte do |b|
      p<<b
    end
    $msg_id+=1
  when :pubrel 
    p=[PUBREL_TYPE,$msg_id >>8 ,$msg_id & 0xff]
    $msg_id+=1
  when :ping
    p=[PINGREQ_TYPE]
    reply_type=:pong
  else
    puts "Error: Strange send?? #{type}"
    return nil
  end
  $iq.clear
  stime=Time.now.to_i
  send_packet p
  timeout=hash[:timeout]||10
  status=:timeout
  m={}
  if hash[:expect] #wait timeout time for reply_type to arrive..
    #puts "waiting for #{hash[:expect]}, timeout: #{timeout}"
    while Time.now.to_i<stime+timeout
      if not $iq.empty?
        m=$iq.pop
        #pp m
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
  #sleep 0.1
end


$t=Thread.new do
  while true do
    begin # emulate blocking recvfrom
      r,stuff=$s.recvfrom_nonblock(200)
     

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
      when REGACK_TYPE
        topic_id=(r[2].ord<<8)+r[3].ord
        m={type: :register_ack,topic_id: topic_id,status: status}
      when PUBREC_TYPE
        msg_id=(r[2].ord<<8)+r[3].ord
        m={type: :pubrec,msg_id: msg_id,status: :ok}
      when PUBACK_TYPE
        m={type: :publish_ack,status: status}
      when PUBCOMP_TYPE
        msg_id=(r[2].ord<<8)+r[3].ord
        m={type: :pubcomp,status: :ok, msg_id: msg_id}
      when PINGRESP_TYPE
        m={type: :pong, status: :ok}
      else
        m={type: :unknown, type_byte: type_byte }
        print "<< "
        r.each_byte do |b|
          printf "%02X ",b
        end
        puts ""
      end
      puts "got: #{m.to_json}"
      $iq<<m if m
    rescue IO::WaitReadable
      IO.select([$s])
      retry
    end
  end
end

def tester

  send :connect,id: "tadaa", expect: :connect_ack do |s,m|
    puts "got connection! status=#{s}, message=#{m.to_json}"
  end
  send :register,topic:"top", expect: :register_ack do |s,m|
    puts "got topic! status=#{s}, message=#{m.to_json}"
  end

  send :publish,msg:"tadaa",topic_id: 1, qos: 2, expect: [:publish_ack,:pubrec] do |s,m|
    puts "got published! status=#{s}, message=#{m.to_json}"
    if s==:ok
      if m[:type]==:pubrec
        send :pubrel,msg_id: m[:msg_id], expect: :pubcomp do |s,m|
          puts "got handshaken! status=#{s}, message=#{m.to_json}"
        end
      end
    end
  end

  while true do
    send :ping, timeout: 3, expect: :pong do |status,message|
      puts "got bong! status=#{status}, message=#{message.to_json}"
    end
    sleep 5
  end
  $t.join
end
