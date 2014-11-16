#!/usr/bin/env ruby
# encode: UTF-8

require "pp"
require 'socket'

$s = UDPSocket.new


CONNECT_TYPE=0x04
CONNACK_TYPE=0x05
REGISTER_TYPE=0x0A
REGACK_TYPE=0x0B
PUBLISH_TYPE=0x0C
PUBACK_TYPE =0x0D
PINGREQ_TYPE=0x16
PINGRESP_TYPE=0x17

RETAIN_FLAG=0x10
WILL_FLAG  =0x08
CLEAN_FLAG =0x04
QOSM1_FLAG =0x60
QOS2_FLAG  =0x40
QOS1_FLAG  =0x20
QOS0_FLAG  =0x00

$msg_id=0x1234
$iq = Queue.new

def send_packet m
  msg=" "
  len=1
  m.each_with_index do |b,i|
    msg[i+1]=b.chr
    len+=1
  end
  msg[0]=len.chr
  print ">> "
  msg.each_byte do |ch|
    printf "%02X ",ch
  end
  puts ""
  $s.send(msg, 0, '20.20.20.21', 1883)
end

def send type,hash={},&block
  puts ""
  pp type,hash
  case type
  when :connect 
    p=[CONNECT_TYPE,CLEAN_FLAG,0x01,0,30]
    hash[:id].each_byte do |b|
      p<<b
    end
    reply_type=:connect_ack
  when :register 
    p=[REGISTER_TYPE,0,0,hash[:msg_id] >>8 ,hash[:msg_id] & 0xff]
    hash[:topic].each_byte do |b|
      p<<b
    end
    reply_type=:register_ack
  when :publish 
    p=[PUBLISH_TYPE,0x20*(hash[:qos]||0),hash[:topic_id] >>8 ,hash[:topic_id] & 0xff,hash[:msg_id] >>8 ,hash[:msg_id] & 0xff]
    hash[:msg].each_byte do |b|
      p<<b
    end
    reply_type=:publish_ack
  when :ping
    p=[PINGREQ_TYPE]
    reply_type=:pong
  else
    puts "Strange send?? #{type}"
    return nil
  end
  $iq.clear
  stime=Time.now.to_i
  send_packet p
  timeout=hash[:timeout]||10
  status=:timeout
  m={}
  if block #wait timeout time for reply_type to arrive..
    puts "waiting for #{reply_type}, timeout: #{timeout}"
    while Time.now.to_i<stime+timeout
      if not $iq.empty?
        m=$iq.pop
        puts "from queue:"
        pp m
        if m[:type]==reply_type
          status=:ok
          break
        else
          puts "wrong type!"
        end
      end
      sleep 0.1
    end
    block.call  status,m
  end
  #sleep 0.1
end


t=Thread.new do
  while true do
    begin # emulate blocking recvfrom
      r,stuff=$s.recvfrom_nonblock(200)
      print "<< "
      r.each_byte do |b|
        printf "%02X ",b
      end
      puts ""

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
      when PUBACK_TYPE
        m={type: :publish_ack,status: status}
      when PINGRESP_TYPE
        m={type: :pong}
      else
        m={type: :unknown, type_byte: type_byte }
      end
      pp m
      $iq<<m if m
    rescue IO::WaitReadable
      IO.select([$s])
      retry
    end
  end
end

send :connect,id: "tadaa" do |s,m|
  puts "got connection! status=#{s}, message=#{m}"
end
send :register,topic:"top",msg_id:$msg_id do |s,m|
  puts "got topic! status=#{s}, message=#{m}"
end
#sleep 0.5
$msg_id+=1
send :publish,msg:"tadaa",topic_id: 1, msg_id:$msg_id, qos: 2 do |s,m|
  puts "got published! status=#{s}, message=#{m}"
end
#sleep 0.5
send :ping, timeout: 3 do |status,message|
  puts "got bong! status=#{status}, message=#{message}"
end



t.join