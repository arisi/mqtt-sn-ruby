mqtt-sn-ruby
============

Ruby toolkit for MQTT-SN, compatible with RSMB, command line tools and API

```
send :connect,id: "tadaaxxx", debug: true, expect: :connect_ack do |s,m| #add will here!
  puts "got connection! status=#{s}, message=#{m.to_json}"
end
topic_id=0

send :register,topic:"top", expect: :register_ack do |s,m|
  if s==:ok
    topic_id=m[:topic_id]
    puts "got topic! status=#{s}, message=#{m.to_json} topic_id= #{topic_id}"
  else
    raise "Error: Register failed!"
  end
end

send :publish,msg:"tadaa0",topic_id: topic_id, qos: 0

send :publish,msg:"tadaa1", retain: true, topic_id: topic_id, qos: 1, expect: [:publish_ack,:pubrec] do |s,m|
  puts "got published! status=#{s}, message=#{m.to_json}"
  if s==:ok
    if m[:type]==:pubrec
      send :pubrel,msg_id: m[:msg_id], expect: :pubcomp do |s,m|
        puts "got handshaken! status=#{s}, message=#{m.to_json}"
      end
    end
  end
end

send :publish,msg:"tadaa2",topic_id: topic_id, qos: 2, debug: true, expect: [:publish_ack,:pubrec] do |s,m|
  puts "got published! status=#{s}, message=#{m.to_json}"
  if s==:ok
    if m[:type]==:pubrec
      send :pubrel,msg_id: m[:msg_id], debug: true, expect: :pubcomp do |s,m|
        puts "got handshaken! status=#{s}, message=#{m.to_json}"
      end
    end
  end
end


3.times do
  send :ping, expect: :pong do |status,message|
    puts "got bong! status=#{status}, message=#{message.to_json}"
  end
  sleep 5
end
puts "Done testing mqtt-sn!"

```
