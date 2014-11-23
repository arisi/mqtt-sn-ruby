#!/usr/bin/env ruby
# encode: UTF-8



def json_gateways request,args,session,event
  if not session or session==0
    return ["text/event-stream",{}]
  end
  @http_sessions[session][:log_pos]=0 if not @http_sessions[session][:log_pos]
  size=$sn.http_log.size
  if @http_sessions[session][:log_pos]!=size
    if size-@http_sessions[session][:log_pos]>30
      @http_sessions[session][:log_pos]=size-30
    end
    loglines=$sn.http_log[@http_sessions[session][:log_pos],size-@http_sessions[session][:log_pos]]
    @http_sessions[session][:log_pos]=size
  else
    loglines=[]
  end
  #puts ">> #{loglines.size} "
  data={
    now:Time.now.to_i,
    jes: [session,event],
    gateways: $sn.gateways,
    clients: $sn.clients,
    state: $sn.state,
    active_gw_id: $sn.active_gw_id,
    options: $sn.options, 
    logpos: @http_sessions[session][:log_pos],
    loglines: loglines,
  }
  #puts  "#{session}/#{event}: #{@http_sessions[session].to_json}"
  
  return ["text/event-stream",data]
end 