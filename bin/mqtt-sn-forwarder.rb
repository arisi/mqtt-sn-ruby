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

options = {forwarder: true}
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
  puts "Starting HTTP services at port #{options[:http_port]}"
  $hp=options[:http_port]
  Thread.new do
    server = TCPServer.new("20.20.20.21",$hp)
    loop do
      Thread.start(server.accept) do |client|
        request = client.gets.split " "
        type="text/html"
        case request[1]
        when '/gw'
          response=$sn.gateways.to_json
          status="200 OK"
          type="text/json"
        when '/cli'
          response=$sn.clients.to_json
          status="200 OK"
          type="text/json"
        else
          status="404 Not Found"
          response="?que"
        end
        client.print "HTTP/1.1 #{status}\r\n" +
               "Content-Type: #{type}\r\n" +
               "Content-Length: #{response.bytesize}\r\n" +
               "Connection: close\r\n"
        client.print "\r\n"
        client.print response 
        client.close
        puts "#{request} -> #{response}"
      end
    end
  end
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