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

options = {forwarder: true,app_name: "mqtt-sn-forwarder"}
OptionParser.new do |opts|
  opts.banner = "Usage: mqtt-sn-sub.rb [options]"

 
  opts.on("-v", "--[no-]verbose", "Run verbosely; creates protocol log on console (false)") do |v|
    options[:verbose] = v
  end
  opts.on("-d", "--[no-]debug", "Produce Debug dump on verbose log (false)") do |v|
    options[:debug] = v
  end
  options[:server_uri] = "udp://localhost:1883"
  opts.on("-s", "--server uri", "URI of the MQTT-SN Server to connect to (udp://localhost:1883)") do |v|
    options[:server_uri] = v
  end
  options[:broadcast_uri] = "udp://225.4.5.6:5000"
  opts.on("-b", "--broadcast uri", "Multicast URI for ADVERTISE, SEARCHGW and GWINFO (udp://225.4.5.6:5000)") do |v|
    options[:broadcast_uri] = v
  end
  opts.on("-l", "--localport port", "MQTT-SN local port to listen (1882)") do |v|
    options[:local_port] = v.to_i
  end 
  options[:gw_id] = 123
  opts.on("-i", "--id GwId", "MQTT-SN id of this GateWay (123)") do |v|
    options[:gw_id] = v.to_i
  end 
  opts.on("-h", "--http port", "Http port for debug/status JSON server (false)") do |v|
    options[:http_port] = v.to_i
  end
end.parse!

$sn=MqttSN.new options
if options[:http_port]
  if File.file? './lib/mqtt-sn-ruby.rb'
    require './lib/mqtt-sn-http.rb'
    puts "using local http lib"
  else
    require 'mqtt-sn-http'
  end
  http_server options
end

puts "MQTT-SN-FORWARDER: #{options.to_json}"

begin
  $sn.forwarder_thread
rescue SystemExit, Interrupt
  puts "\nExiting after Disconnect\n"
rescue => e
  puts "\nError: '#{e}' -- Quit after Disconnect\n"
  pp e.backtrace
end
$sn.kill_clients #if $sn

puts "MQTT-SN-FORWARDER Done."