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
  opts.on("-h", "--host host", "MQTT-SN target Host to connect (localhost)") do |v|
    options[:server] = v
  end
  opts.on("-p", "--port port", "MQTT-SN target Port to connect (1883)") do |v|
    options[:port] = v.to_i
  end
  opts.on("-i", "--localip ip", "MQTT-SN Local ip to bind (127.0.0.1)") do |v|
    options[:local_ip] = v
  end
  opts.on("-l", "--localport port", "MQTT-SN local port to listen (1882)") do |v|
    options[:local_port] = v.to_i
  end
end.parse!

puts "MQTT-SN-FORWARDER: #{options.to_json}"
begin
  MqttSN.forwarder options
rescue SystemExit, Interrupt
  puts "\nExiting after Disconnect\n"
rescue => e
  puts "\nError: '#{e}' -- Quit after Disconnect\n"
  pp e.backtrace
end

puts "MQTT-SN-FORWARDER Done."