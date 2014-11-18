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
  options[:server_uri] = "udp://localhost:1883"
  opts.on("-s", "--server uri", "URI of the MQTT-SN Server to connect to (udp://localhost:1883)") do |v|
    options[:server_uri] = v
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