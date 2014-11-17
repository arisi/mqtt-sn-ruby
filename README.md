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
 sn3.subscribe "sensors/+/floor",qos:2 do |status,message|
    puts "Measurement: #{status},#{message.to_json}"
  end
sn.disconnect

```

for more up-to-date examples, see the included test.rb


