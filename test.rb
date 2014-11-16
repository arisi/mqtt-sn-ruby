#!/usr/bin/env ruby
# encode: UTF-8

require "pp"
require 'socket'
require 'json'

if File.file? './lib/mqtt-sn-ruby.rb'
  require './lib/mqtt-sn-ruby.rb'
  puts "using local lib"
else
  require 'mqtt-sn-ruby'
  puts "using gem lib"
end

puts "Testing mqtt-sn.."

sn=MqttSN.new debug: true
sn2=MqttSN.new debug: false

sn2.send :connect,id: "tadaayyyy", debug: true, expect: :connect_ack do |s,m| #add will here!
  puts "got connection! status=#{s}, message=#{m.to_json}"
end


sn.send :connect,id: "tadaaxxx", debug: true, expect: :connect_ack do |s,m| #add will here!
  puts "got connection! status=#{s}, message=#{m.to_json}"
end
topic_id=0

sn2.send :ping, expect: :pong do |status,message|
    puts "got bong from 2! status=#{status}, message=#{message.to_json}"
end

sn.send :register,topic:"top", expect: :register_ack do |s,m|
  if s==:ok
    topic_id=m[:topic_id]
    puts "got topic! status=#{s}, message=#{m.to_json} topic_id= #{topic_id}"
  else
    raise "Error: Register failed!"
  end
end

sn.send :publish,msg:"tadaa0",topic_id: topic_id, qos: 0

sn.send :publish,msg:"tadaa1", retain: true, topic_id: topic_id, qos: 1, expect: [:publish_ack,:pubrec] do |s,m|
  puts "got published! status=#{s}, message=#{m.to_json}"
  if s==:ok
    if m[:type]==:pubrec
      sn.send :pubrel,msg_id: m[:msg_id], expect: :pubcomp do |s,m|
        puts "got handshaken! status=#{s}, message=#{m.to_json}"
      end
    end
  end
end

sn.send :publish,msg:"tadaa2",topic_id: topic_id, qos: 2, debug: true, expect: [:publish_ack,:pubrec] do |s,m|
  puts "got published! status=#{s}, message=#{m.to_json}"
  if s==:ok
    if m[:type]==:pubrec
      sn.send :pubrel,msg_id: m[:msg_id], debug: true, expect: :pubcomp do |s,m|
        puts "got handshaken! status=#{s}, message=#{m.to_json}"
      end
    end
  end
end

sn.send :disconnect, expect: :disconnect do |status,message|
  puts "got disconnecter status=#{status}, message=#{message.to_json}"
end


2.times do
  sn.send :ping, timeout: 1,expect: :pong do |status,message|
    if status==:ok
      puts "got bong! status=#{status}, message=#{message.to_json}"
    else
      puts "no pong"
      break
    end
  end
  sleep 5
end


sn=nil
sn2=nil
puts "Done testing mqtt-sn!"

