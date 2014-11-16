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

sn.will_and_testament "top","testamentti"
sn.connect "eka"
sn2.connect "toka"

topic_id=0

sn2.ping

sn.register_topic "jeesus/perkele/toimii"
sn.publish "top","perkkule0",0
sn.publish "top","perkkule1",1
sn.publish "top","perkkule2",2

sn2.publish "top","2perkkule0",0
sn2.publish "top","2perkkule1",1
sn2.publish "top","2perkkule2",2

sn2.disconnect

5.times do
  sn.ping
  sleep 0.5
end

sn.disconnect


puts "Done testing mqtt-sn!"

