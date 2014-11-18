require 'socket'
socket = UDPSocket.open
socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_BROADCAST, true)
socket.send("sample", 0, '255.255.255.255', 4321)