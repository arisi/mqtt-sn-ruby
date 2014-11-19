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
  options[:server_uri] = "udp://localhost:1883"
  opts.on("-s", "--server uri", "URI of the MQTT-SN Server to connect to (udp://localhost:1883)") do |v|
    options[:server_uri] = v
  end
  opts.on("-q", "--qos level", "QoS level (0)") do |v|
    options[:qos] = v.to_i
  end
  opts.on("-i", "--id id", "This client's id -- free choice (hostname-pid)") do |name|
    options[:id] = name
  end
  opts.on("-m", "--msg msg", "Message to send (test_value)") do |msg|
    options[:msg] = msg
  end
  opts.on("-t", "--topic topic", "Topic to use (test/message/123)") do |topic|
    options[:topic] = topic
  end
end.parse!
#require 'ruby-prof'
#RubyProf.start
puts "MQTT-SN-PUB: #{options.to_json}"
begin
  sn=MqttSN.new options
  sn.connect options[:id]
  sn.send :searchgw #replies may or may not come -- even multiple!
  sn.publish options[:topic]||"test/message/123", options[:msg]||"test_value", qos: options[:qos]
  puts "Sent ok."
  while not sn.log_empty?
    sleep 0.1
  end
rescue SystemExit, Interrupt
  puts "\nExiting after Disconnect\n"
rescue => e
  puts "\nError: '#{e}' -- Quit after Disconnect\n"
  pp e.backtrace
end
sn.disconnect if sn

puts "MQTT-SN-PUB Done."

#result = RubyProf.stop

# Print a flat profile to text
#printer = RubyProf::FlatPrinter.new(result)
#printer.print(STDOUT)