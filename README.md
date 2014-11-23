#mqtt-sn-ruby

A simple Ruby gem for MQTT-SN, compatible with RSMB, minimal depenencies (=no gems), with command line tools and API

This gem has full-fledged CLI and API for MQTT-SN, all in Ruby.

You can use it for testing, and for building gateways from packet radio ... or CAN, or whatever.

You can use our free and open mqtt-sn-server at udp://mqtt.fi:1882 for tests!

##Supported Features:
- QoS -1,0,1,2
- LWT (Last Will and Testament)
- Transparent forwarder -- from UDP to UDP 
- ADVERTISE, SEARCHGW and GWINFO autodiscovery
- Multicast on UDP to emulate radio network broadcast, you can leave gateway unspecified -- it will be discovered!
- Verbose log now with timestamp and correct ports et al.
- Keepalive ping 
- Http server at Publish & Forwarder utils. Allows JSON-status queries.
- Supports 2-character short topics, detected automatically
- Supports Predefined Topics (although RSMB does not yet(?) support them), To use predefined, set topic as "=123"
- example send.rb and recv.rb
- free test broker available at mqtt.fi sockets 1882 and 1883 -- feel free to test!
- Minimal c client lib and demo pub in c-subdir


##New Features:
- Web server: statistics,status and protocol trace log for subscribe & forwarder utility, with SSE and raw sockets ;) 

##Features in near future:
- support for packet radio via FM <--> UDP server

##Installation

First install the gem:

```asciidoc
$ gem install mqtt-sn-ruby
```
##Quick test

For a simple publish: (using free mqtt-sn server)

```ruby
require 'mqtt-sn-ruby'

sn=MqttSN.new server_uri: "udp://mqtt.fi:1882"
sn.pub msg: "testing"
sn.disconnect 
```

and for a simple subscribe: (using free mqtt-sn server)

```ruby
require 'mqtt-sn-ruby'

sn=MqttSN.new server_uri: "udp://mqtt.fi:1882"
sn.sub  do |status,msg|
  sn.note "Got Message '#{msg[:msg]}' with Topic '#{msg[:topic]}'"
end
```
This gem also provides some command line utilities:

(Multicast UDP is used to emulate radio network's broadcast.)

- Publish utility, use this to subscribe messages.
```asciidoc
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
Sample run:
``` asciidoc
$ mqtt-sn-pub.rb -t pe -m hello_world -q 1 --server udp://mqtt.fi:1882 -v

2014-11-22T12:13:59+02:00: Using Default Gateway: udp://mqtt.fi:1882
2014-11-22T12:13:59+02:00: Opening Gateway 0: udp://mqtt.fi:1882
2014-11-22T12:13:59+02:00: MQTT-SN-PUB: {"topic":"pe","msg":"hello_world","qos":1,"server_uri":"udp://mqtt.fi:1882","verbose":true}
2014-11-22T12:13:59+02:00: Connecting as 'mqtt-sn-ruby-11069'
2014-11-22T12:13:59+02:00: (  0) | od udp://mqtt.fi:1882       <- udp://0.0.0.0:53903      | {"type":"connect","flags":0,"duration":25,"client_id":"mqtt-sn-ruby-11069","status":"ok"}
2014-11-22T12:13:59+02:00: (  0) | id udp://mqtt.fi:1882       -> udp://0.0.0.0:53903      | {"type":"connect_ack","status":"ok"}
2014-11-22T12:13:59+02:00: (  0) | od udp://mqtt.fi:1882       <- udp://0.0.0.0:53903      | {"type":"publish","qos":1,"topic_id":28773,"topic_type":"short","topic":"pe","msg_id":1,"msg":"hello_world","status":"ok"}
2014-11-22T12:13:59+02:00: (  0) | id udp://mqtt.fi:1882       -> udp://0.0.0.0:53903      | {"type":"publish_ack","topic_id":0,"msg_id":1,"status":"ok"}
Sent ok.
2014-11-22T12:14:00+02:00: (  0) | od udp://mqtt.fi:1882       <- udp://0.0.0.0:53903      | {"type":"disconnect","status":"ok"}
2014-11-22T12:14:00+02:00: (  0) | id udp://mqtt.fi:1882       -> udp://0.0.0.0:53903      | {"type":"disconnect","status":"ok"}
MQTT-SN-PUB Done.
```

- Subscription utility, use this to subscribe messages. Press Control-C to Quit.
```asciidoc
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

And sample run (without verbose debugging):

``` asciidoc
$ bin/mqtt-sn-sub.rb  --server udp://mqtt.fi:1882 

2014-11-22T12:16:02+02:00: Using Default Gateway: udp://mqtt.fi:1882
MQTT-SN-SUB: {"broadcast_uri":"udp://225.4.5.6:5000","topic":"#","server_uri":"udp://mqtt.fi:1882"}
2014-11-22T12:16:02+02:00: Opening Gateway 0: udp://mqtt.fi:1882
2014-11-22T12:16:02+02:00: Connecting..
2014-11-22T12:16:02+02:00: Connecting as 'mqtt-sn-ruby-11109'
2014-11-22T12:16:02+02:00: connect result: ok {:type=>:connect_ack, :status=>:ok}
2014-11-22T12:16:02+02:00: Subscribing..
2014-11-22T12:16:02+02:00: Subscribed Ok! Waiting for Messages!
2014-11-22T12:16:08+02:00: Got Message 'hello_world' with Topic 'pe'

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

Sample forwarder run and log:

``` asciidoc
$ mqtt-sn-forwarder.rb -l 1882 -v -d  --server udp://20.20.20.21:1883 -i 56

2014-11-22T12:16:07+02:00: + 178.251.144.67:48247
2014-11-22T12:16:07+02:00: [ 56] | cs udp://178.251.144.67:482 -> udp://20.20.20.21:1883   | {"type":"connect","flags":0,"duration":25,"client_id":"mqtt-sn-ruby-11146","status":"ok"}
2014-11-22T12:16:07+02:00: [ 56] | sc udp://178.251.144.67:482 <- udp://20.20.20.21:1883   | {"type":"connect_ack","status":"ok"}
2014-11-22T12:16:07+02:00: [ 56] | cs udp://178.251.144.67:482 -> udp://20.20.20.21:1883   | {"type":"publish","qos":1,"topic_id":28773,"topic_type":"short","topic":"pe","msg_id":1,"msg":"hello_world","status":"ok"}
2014-11-22T12:16:07+02:00: [ 56] | sc udp://178.251.144.67:482 <- udp://20.20.20.21:1883   | {"type":"publish_ack","topic_id":0,"msg_id":1,"status":"ok"}
2014-11-22T12:16:07+02:00: [ 56] | sc udp://178.251.144.67:378 <- udp://20.20.20.21:1883   | {"type":"publish","qos":0,"topic_id":28773,"topic_type":"short","topic":"pe","msg_id":1,"msg":"hello_world","status":"ok"}
2014-11-22T12:16:08+02:00: [ 56] | cs udp://178.251.144.67:482 -> udp://20.20.20.21:1883   | {"type":"disconnect","status":"ok"}
2014-11-22T12:16:08+02:00: [ 56] | sc udp://178.251.144.67:482 <- udp://20.20.20.21:1883   | {"type":"disconnect","status":"ok"}
2014-11-22T12:16:08+02:00: - 178.251.144.67:48247
```

You can easily check the packets as they flow back and forth between client and broker.

##RSMB Installation notes:

First get the sources from http://git.eclipse.org/c/mosquitto/org.eclipse.mosquitto.rsmb.git/

To compile and run, you can:

``` asciidoc
git clone git://git.eclipse.org/gitroot/mosquitto/org.eclipse.mosquitto.rsmb.git
cd org.eclipse.mosquitto.rsmb/rsmb/src
make
echo listener 1883 INADDR_ANY mqtts >mqtt-sn.conf
./broker_mqtts mqtt_sn.conf

20141122 123828.692 CWNAN9999I Really Small Message Broker
20141122 123828.692 CWNAN9998I Part of Project Mosquitto in Eclipse
(http://projects.eclipse.org/projects/technology.mosquitto)
20141122 123828.692 CWNAN0049I Configuration file name is mqtt-sn.conf
20141122 123828.692 CWNAN0053I Version 1.3.0.2, Nov 22 2014 12:37:37
20141122 123828.692 CWNAN0054I Features included: bridge MQTTS 
20141122 123828.692 CWNAN9993I Authors: Ian Craggs (icraggs@uk.ibm.com), Nicholas O'Leary
20141122 123828.692 CWNAN0300I MQTT-S protocol starting, listening on port 1883
.....

```
And you have your own broker up and running!


