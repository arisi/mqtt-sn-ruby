require 'socket'
server = UDPSocket.open
server.bind('0.0.0.0', 1882)
while true do
  p server.recvfrom(10)
end