mqtt-sn-ruby
============

A simple Ruby gem for MQTT-SN, compatible with RSMB, minimal depenencies (=no gems), with command line tools and API

Still in very early phases, check the test.rb for current usage.

But soon, it will be full-fledged CLI and API for MQTT-SN, all in Ruby.

You can use it for testing, and for building gateways from packet radio ... or CAN, or whatever.

Supported Features:
- QoS 0,1,2
- LWT (Last Will and Testament)
- Transparent forwarder -- from UDP to UDP 
- ADVERTISE, SEARCHGW and GWINFO autodiscovery

New Features:
- Multicast on UDP to emulate radio network broadcast, you can leave gateway unspecified -- it will be discovered!
- Verbose log now with timestamp and correct ports et al.
- Keepalive ping 
- Http server at Publish & Forwarder utils. Allows JSON-status queries.

First install the gem:

```shell
$ gem install mqtt-sn-ruby
```

and for a simple publish:

```ruby
require 'mqtt-sn-ruby'

sn=MqttSN.new debug: true
sn.connect "mynode"
sn.publish "sensors/room1/floor","{value: 123}",qos: 0
sn.disconnect
```

and for a simple subscibe:

```ruby
require 'mqtt-sn-ruby'

sn=MqttSN.new debug: true
sn.connect "mynode2"
sn.subscribe "sensors/+/floor",qos:2 do |status,message|
  puts "Measurement: #{status},#{message.to_json}"
end
sn.disconnect
```
gem also provides some command line utilities:
(Multicast UDP is used to emulate radio network's broadcast.)

- Publish utility, use this to subscribe messages.
```shell
$ mqtt-sn-pub.rb 

Usage: mqtt-sn-sub.rb [options]
    -v, --[no-]verbose     Run verbosely (false)
    -d, --[no-]debug       Produce Debug dump on console (false)
    -s, --server uri       URI of the MQTT-SN Server to connect to. Example udp://localhost:1883. Default: Use Autodiscovery.
    -q, --qos level        QoS level (0)
    -i, --id id            This client id -- free choice (hostname-pid)
    -m, --msg msg          Message to send (test_value)
    -t, --topic topic      Topic to subscribe (test/message/123)
```

- Subscription utility, use this to subscribe messages. Press Control-C to Quit.
```shell
$ mqtt-sn-sub.rb 

Usage: mqtt-sn-sub.rb [options]
    -v, --[no-]verbose     Run verbosely (false)
    -d, --[no-]debug       Produce Debug dump on console (false)
    -s, --server uri       URI of the MQTT-SN Server to connect to.  Example udp://localhost:1883. Default: Use Autodiscovery.
    -q, --qos level        QoS level (0)
    -i, --id id            This client id -- free choice (hostname-pid)
    -t, --topic topic      Topic to subscribe (test/message/123)
    -k, --keepalive dur    Keepalive timer, in seconds. Will ping with this interval. (25)

```

- Forwarder, from UDP server:socket to another UDP server:socket.  Displays packets on screen as they are forwarder, great for debugging! Press Control-C to Quit.
```shell
$ mqtt-sn-forward.rb 

Usage: mqtt-sn-sub.rb [options]
    -v, --[no-]verbose     Run verbosely (false)
    -d, --[no-]debug       Produce Debug dump on console (false)
    -s, --server uri       URI of the MQTT-SN Server to connect to (udp://localhost:1883)
    -l, --localport port   MQTT-SN local port to listen (1882)
    -h, --http port        Http port for debug/status JSON server (false)
```

Sample log from forwarder:

```
C 20.20.20.21:43721  -> 20.20.20.21:38284  | {"type":"register","topic_id":0,"msg_id":1,"topic":"test/uusi","status":"ok"}
S 20.20.20.21:43721  <- 20.20.20.21:38284  | {"type":"register_ack","topic_id":1,"status":"ok"}
C 20.20.20.21:43721  -> 20.20.20.21:38284  | {"type":"publish","qos":2,"topic_id":1,"msg_id":2,"msg":"hello!!","status":"ok"}
S 20.20.20.21:43721  <- 20.20.20.21:38284  | {"type":"pubrec","msg_id":2,"status":"ok"}
C 20.20.20.21:43721  -> 20.20.20.21:38284  | {"type":"pub_rel","msg_id":2,"status":"ok"}
S 20.20.20.21:59089  <- 20.20.20.21:46649  | {"type":"register","topic_id":1,"msg_id":1,"topic":"test/uusi","status":"ok"}
S 20.20.20.21:43721  <- 20.20.20.21:38284  | {"type":"pubcomp","status":"ok","msg_id":2}
C 20.20.20.21:59089  -> 20.20.20.21:46649  | {"type":"register_ack","topic_id":1,"status":"ok"}
S 20.20.20.21:59089  <- 20.20.20.21:46649  | {"type":"publish","qos":2,"topic_id":1,"msg_id":2,"msg":"hello!!","status":"ok"}
C 20.20.20.21:59089  -> 20.20.20.21:46649  | {"type":"pubrec","msg_id":2,"status":"ok"}
S 20.20.20.21:59089  <- 20.20.20.21:46649  | {"type":"pub_rel","msg_id":2,"status":"ok"}
C 20.20.20.21:59089  -> 20.20.20.21:46649  | {"type":"pubcomp","status":"ok","msg_id":2}
C 20.20.20.21:43721  -> 20.20.20.21:38284  | {"type":"disconnect","status":"ok"}
S 20.20.20.21:43721  <- 20.20.20.21:38284  | {"type":"disconnect","status":"ok"}
```

for more up-to-date examples, see the included test.rb


