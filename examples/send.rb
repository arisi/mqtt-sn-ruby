#!/usr/bin/env ruby

require 'mqtt-sn-ruby'

sn=MqttSN.new server_uri: "udp://mqtt.fi:1882"
sn.pub msg: "testing"
sn.disconnect 