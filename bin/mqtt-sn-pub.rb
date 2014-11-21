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
  opts.banner = "Usage: mqtt-sn-pub.rb [options]"

  opts.on("-v", "--[no-]verbose", "Run verbosely (false)") do |v|
    options[:verbose] = v
  end
  opts.on("-d", "--[no-]debug", "Produce Debug dump on console (false)") do |v|
    options[:debug] = v
  end
  opts.on("-s", "--server uri", "URI of the MQTT-SN Server to connect to. Example udp://localhost:1883. Default: Use Autodiscovery.") do |v|
    options[:server_uri] = v
  end
  opts.on("-q", "--qos level", "QoS level (0). When using QoS -1, you must provide either Short Topic (2-char) or Topic_Id") do |v|
    options[:qos] = v.to_i
  end
  opts.on("-i", "--id id", "This client's id -- free choice (hostname-pid)") do |name|
    options[:id] = name
  end
  opts.on("-m", "--msg msg", "Message to send (test_value)") do |msg|
    options[:msg] = msg
  end
  opts.on("-t", "--topic topic", "Topic to use (test/message/123). For predefined Topics, use this notation '=123'") do |topic|
    options[:topic] = topic
  end
  
end.parse!

puts "MQTT-SN-PUB: #{options.to_json}"
begin
  sn=MqttSN.new options
  sent=false
  if options[:qos]==-1
    sn.publish options[:topic]||"XX", options[:msg]||"test_value", qos: options[:qos]
    puts "Sent."
  else
    while not sent
      sn.connect options[:id] do |s,m|
        if s==:ok
          sn.publish options[:topic]||"test/message/123", options[:msg]||"test_value", qos: options[:qos]
          puts "Sent ok."
          sent=true
        else
          sn.disconnect
        end
      end
    end
  end
  sn.log_flush
rescue SystemExit, Interrupt
  puts "\nExiting after Disconnect\n"
rescue => e
  puts "\nError: '#{e}' -- Quit after Disconnect\n"
  pp e.backtrace
end
sn.disconnect if sn

puts "MQTT-SN-PUB Done."
