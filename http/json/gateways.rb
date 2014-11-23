#!/usr/bin/env ruby
# encode: UTF-8
$jes=123
def json_gateways request
  #puts "json_gateways!"
  $jes+=1
  data={
    now:Time.now.to_i,
    jes: $jes,
    gateways: $sn.gateways,
    state: $sn.state,
    active_gw_id: $sn.active_gw_id,
  }
  #pp data
  return ["text/event-stream",data]
end 