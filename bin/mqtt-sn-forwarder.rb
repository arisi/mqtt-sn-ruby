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
  opts.on("-l", "--localport port", "MQTT-SN local port to listen (1882)") do |v|
    options[:local_port] = v.to_i
  end 
  opts.on("-h", "--http port", "Http port for debug/status JSON server (false)") do |v|
    options[:http_port] = v.to_i
  end
end.parse!


if options[:http_port]
  require "sinatra/base"
  puts "Starting HTTP services at port #{options[:http_port]}"
  @hp=options[:http_port]
  class MySinatra < Sinatra::Base
    set :bind, '0.0.0.0'
    set :port, @hp

    get "/clients" do
      content_type :json
      MqttSN.get_clients.to_json
    end
    get "/gateways" do
      content_type :json
      MqttSN.get_gateways.to_json
    end
  end
  Thread.new do
    MySinatra.run!
  end
end
options[:forwarder]=true
puts "MQTT-SN-FORWARDER: #{options.to_json}"
begin
  f=MqttSN.new options
rescue SystemExit, Interrupt
  puts "\nExiting after Disconnect\n"
rescue => e
  puts "\nError: '#{e}' -- Quit after Disconnect\n"
  pp e.backtrace
end

puts "MQTT-SN-FORWARDER Done."