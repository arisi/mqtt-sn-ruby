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
sn3=MqttSN.new debug: true


sn.will_and_testament "top","testamentti"
sn.connect "eka"

sn2.connect "toka"

sn3.connect "kolmas"

Thread.new do
  sn3.subscribe "eka/2",qos:2 do |s,m|
    puts ">>>>>>>>>>>> subscribe got: #{s},#{m}"
  end
end
sleep 1
sn3.unsubscribe "eka/2" # this can cause race condition ... must wait until pevious subscribe has received ack.. until exec unsubsribe -- a mutex during wait?

topic_id=0
sn.will_and_testament "top2","testamentti2"

sn2.ping
sn3.subscribe "eka/3",qos:2 
#sn.register_topic "jeesus/perkele/toimii"
sn.publish "eka/1","perkkule0",qos: 0
sn.publish "eka/2","perkkule1",qos: 1
sn.publish "eka/3","perkkule2",qos: 2


sn2.publish "eka/4","2perkkule0",qos: 0
sn2.publish "eka/5","2perkkule1rrrr",qos: 1, retain: true
sn2.publish "eka/6","2perkkule2",qos: 2
sn2.disconnect

#puts "----------------- sleep"
#sn2.goto_sleep 4

5.times do
  sn.ping
  sleep 0.5
end


sn.disconnect
sn3.disconnect


puts "Done testing mqtt-sn!"

