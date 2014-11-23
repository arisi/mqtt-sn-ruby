#!/usr/bin/env ruby
# encode: UTF-8


def json_action request,args,session,event
  #$sn.pub msg: "jees123", server_uri: "udp://20.20.20.21:1882"
  topic="top"
  msg=args['msg']||"test_message"
  topic=args['topic']||"XX"
  qos=(args['qos']||0).to_i
  if args['retain']=="true"
    retain=true
  else
    retail=nil
  end
  pp args
  pp retain
  $sn.publish topic, msg, qos: qos, retain: retain
  data={jee: 123}
  return ["text/json",data]
end