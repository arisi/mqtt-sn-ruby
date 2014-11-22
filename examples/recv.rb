#!/usr/bin/env ruby

require 'mqtt-sn-ruby'

begin
  sn=MqttSN.new server_uri: "udp://mqtt.fi:1882", verbose: true
  sn.sub  do |status,msg|
    sn.note "Got Message '#{msg[:msg]}' with Topic '#{msg[:topic]}'"
  end
rescue SystemExit, Interrupt
  puts "\nExiting after Disconnect\n"
end
sn.disconnect 
puts "Exiting."