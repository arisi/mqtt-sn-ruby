mqtt-sn-ruby
============

Ruby toolkit for MQTT-SN, compatible with RSMB, command line tools and API

Still in very early phases, check the test.rb for current usage.

But soon, it will be full-fledged CLI and API for MQTT-SN, all in Ruby.

You can use it for testing, and for building gateways from packet radio ... or CAN, or whatever.

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


- Publish utility, use this to subscribe messages.
```shell
$ mqtt-sn-pub.rb 

Usage: mqtt-sn-sub.rb [options]
    -v, --[no-]verbose     Run verbosely (false)
    -d, --[no-]debug       Produce Debug dump on console (false)
    -h, --host host        MQTT-SN Host to connect (localhost)
    -p, --port port        MQTT-SN Port to connect (1883)
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
    -h, --host host        MQTT-SN Host to connect (localhost)
    -p, --port port        MQTT-SN Port to connect (1883)
    -q, --qos level        QoS level (0)
    -i, --id id            This client id -- free choice (hostname-pid)
    -t, --topic topic      Topic to subscribe (test/message/123)
```

for more up-to-date examples, see the included test.rb


