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

options = {app_name: "mqtt-sn-sub"}
OptionParser.new do |opts|
  opts.banner = "Usage: #{options[:app_name]}.rb [options]"

  opts.on("-v", "--[no-]verbose", "Run verbosely; creates protocol log on console (false)") do |v|
    options[:verbose] = v
  end
  opts.on("-d", "--[no-]debug", "Produce Debug dump on verbose log (false)") do |v|
    options[:debug] = v
  end
  opts.on("-s", "--server uri","URI of the MQTT-SN Server to connect to. Example udp://localhost:1883. Default: Use Autodiscovery.") do |v|
    options[:server_uri] = v
  end
  options[:broadcast_uri] = "udp://225.4.5.6:5000"
  opts.on("-b", "--[no-]broadcast uri", "Multicast URI for Autodiscovery: ADVERTISE, SEARCHGW and GWINFO (udp://225.4.5.6:5000)") do |v|
    options[:broadcast_uri] = v
  end
  opts.on("-q", "--qos level", "QoS level -1,0,1 or 2. (0)") do |v|
    options[:qos] = v.to_i
  end
  opts.on("-i", "--id id", "This client's id -- free choice (hostname-pid)") do |name|
    options[:id] = name
  end
  options[:topic] = "#"
  opts.on("-t", "--topic topic", "Topic to Subscribe (#)") do |topic|
    options[:topic] = topic
  end
  opts.on("-h", "--http port", "Http port for debug/status JSON server (false)") do |v|
    options[:http_port] = v.to_i
  end
  opts.on("-k", "--keepalive dur", "Keepalive timer, in seconds. Will ping Server with this interval. (25)") do |topic|
    options[:keepalive] = topic
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

puts "MQTT-SN-SUB: #{options.to_json}"
begin
  $sn.sub options do |status,msg|
    $sn.note "Got Message '#{msg[:msg]}' with Topic '#{msg[:topic]}'"
  end
rescue SystemExit, Interrupt
  puts "\nExiting after Disconnect\n"
rescue => e
  puts "\nError: '#{e}' -- Quit after Disconnect\n"
  pp e.backtrace
end
$sn.disconnect if $sn

puts "MQTT-SN-SUB Done."

