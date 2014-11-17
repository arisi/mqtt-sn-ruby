#!/usr/bin/env ruby
# encode: UTF-8

require "pp"
require 'socket'
require 'json'
require 'optparse'
if File.file? './lib/mqtt-sn-ruby.rb'
  require './lib/mqtt-sn-ruby.rb'
  puts "using local lib"
else
  require 'mqtt-sn-ruby'
end

options = {}
OptionParser.new do |opts|
  opts.banner = "Usage: mqtt-sn-sub.rb [options]"

  opts.on("-v", "--[no-]verbose", "Run verbosely (false)") do |v|
    options[:verbose] = v
  end
  opts.on("-d", "--[no-]debug", "Produce Debug dump on console (false)") do |v|
    options[:debug] = v
  end
  opts.on("-h", "--host host", "MQTT-SN Host to connect (localhost)") do |v|
    options[:server] = v
  end
  opts.on("-p", "--port port", "MQTT-SN Port to connect (1883)") do |v|
    options[:port] = v.to_i
  end
  opts.on("-q", "--qos level", "QoS level (0)") do |v|
    options[:qos] = v.to_i
  end
  opts.on("-i", "--id id", "This client's id -- free choice (hostname-pid)") do |name|
    options[:id] = name
  end
  opts.on("-t", "--topic topic", "Topic to subscribe (test/message/123)") do |topic|
    options[:topic] = topic
  end
end.parse!

puts "MQTT-SN-SUB: #{options.to_json}"
begin
  sn=MqttSN.new options
  sn.connect options[:id]
  sn.subscribe options[:topic]||"test/message/123", qos: options[:qos] do |s,m|
    if s==:sub_ack
      puts "Subscribed Ok! Waiting for Messages!"
    else
      puts "Got Message: #{m}"
    end
  end
  puts "Disconnected..."
rescue SystemExit, Interrupt
  puts "\nExiting after Disconnect\n"
rescue => e
  puts "\nError: '#{e}' -- Quit after Disconnect\n"
end
sn.disconnect

puts "MQTT-SN-SUB Done."

