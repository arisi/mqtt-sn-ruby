
now=0

update_status = (data) ->
  #console.log data
  now=data.now
  html="<table><tr><th>gw_id</th><th>uri</th><th>source</th><th>stamp</th><th>last_use</th><th>last_ping</th><th>last_send</th><th>counter_send</th><th>last_recv</th><th>counter_recv</th></tr>"
  for k,v of data.gateways
    k=parseInt(k,10)
    col="white"
    if data.active_gw_id== k
      col="#d0ffd0" 
    html+="<tr bgcolor='#{col}'>"
    html+="<td>#{k}</td>"
    html+="<td>#{v.uri}</td>"
    html+="<td>#{v.source}</td>"
    html+="<td>#{now-v.stamp}</td>"
    if v.last_use
      html+="<td>#{now-v.last_use}</td>"
    else
      html+="<td></td>"
    if v.last_ping
      html+="<td>#{now-v.last_ping}</td>"
    else
      html+="<td></td>"
      
    if v.last_send
      html+="<td>#{now-v.last_send}</td>"
    else
      html+="<td></td>"
    html+="<td>#{v.counter_send}</td>"

    if v.last_recv
      html+="<td>#{now-v.last_recv}</td>"
    else
      html+="<td></td>"
    html+="<td>#{v.counter_recv}</td>"
    html+="</tr>"

  html+="</table>"
  #console.log html
  $(".data").html(html)
  $(".state").html(data.state)
  $(".active_gw_id").html(data.active_gw_id)


xxx = () ->
  $.ajax
    url: "/gateways.json"
    type: "GET"
    data: "123"
    processData: false
    contentType: false
    success: (data) ->
      console.log "ajax returns: ", data
      $(".data").html(html)

      return
    error: (xhr, ajaxOptions, thrownError) ->
      alert thrownError
      return


$ ->
  console.log "tadaa"
  #update_gw()
  #setInterval(->
  #  update_gw()
  #  return
  #, 200000)
  stream = new EventSource("/gateways.json")
  stream.addEventListener "message", (event) ->
    update_status($.parseJSON(event.data))
    return
  


  
