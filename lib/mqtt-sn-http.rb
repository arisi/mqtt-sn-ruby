#!/usr/bin/env ruby
# encode: UTF-8

require "haml"
require "coffee-script"

def http_server options
  prev_t={}
  #@http_log=[]
  puts "Starting HTTP services at port #{options[:http_port]}"
  if File.directory? './http'
    $http_dir="http/"
  else
    $http_dir = File.join( Gem.loaded_specs['mqtt-sn-ruby'].full_gem_path, 'http/')
  end

  Thread.new(options[:http_port],options[:app_name]) do |http_port,http_app|
    server = TCPServer.new("0.0.0.0",http_port)
    @http_sessions={}
    http_session_counter=1
    loop do
      Thread.start(server.accept) do |client|
        begin
          request = client.gets.split " "
          status="200 OK"
          type="text/html"
          req=request[1]
          req="/#{http_app}.html" if req=="/" or req=="/index.htm" or req=="/index.html"
          req,args=req.split "\?"
          #puts "req: #{req}"
          if req[/\.html$/] and File.file?(fn="#{$http_dir}haml#{req.gsub('.html','.haml')}")
            contents = File.read(fn)
            response=Haml::Engine.new(contents).render
          elsif req[/\.js$/] and File.file?(fn="#{$http_dir}coffee#{req.gsub('.js','.coffee')}")
            type="application/javascript"
            contents = File.read(fn)
            begin
              response=CoffeeScript.compile contents
            rescue => e
              response="Coffee Compile error: #{e}"
            end
          elsif req[/^\/(.+)\.json$/] and File.file?(fn="#{$http_dir}json#{req.gsub('.json','.rb')}")
            req[/\/(.+).json$/] 
            act=$1
            #puts "act:#{act} args:#{args}"
            t=File.mtime(fn)
            if not prev_t[fn] or prev_t[fn]<t
              begin
                load_ok=load fn
                prev_t[fn]=t
              rescue Exception => e
                puts "**** RELOAD #{fn} failed:  #{e}"
                pp e.backtrace
                response=[{act: :error, msg:"Error loading JSON",alert: "Load error #{e} in #{fn}"}].to_json
                type="text/json"
                status="404 Not Found"
              end
            end
            if type!="text/event-stream" and status=="200 OK"
              begin
                type,response=eval "json_#{act} request,0,0"  #event handlers get called with zero session => init :)
                response=response.to_json
              rescue => e
                puts "**** AJAX EXEC #{fn} failed:  #{e}"
                pp e.backtrace
                response=[{act: :error, msg:"Error executing JSON",alert: "Syntax error '#{e}' in '#{fn}'"}].to_json
                type="text/json"
              end
            end
          elsif req[/\.css$/] and File.file?(fnc="#{$http_dir}css#{req}")
            type="text/css"
            contents = File.read(fnc)
            response=contents
          else
            status="404 Not Found"
            response="Not Found: #{request[1]}"
          end
          client.print "HTTP/1.1 #{status}\r\n" +
                 "Content-Type: #{type}\r\n"
          if type!="text/event-stream"
            client.print "Content-Length: #{response.bytesize}\r\n"
            client.print "Connection: close\r\n"
            client.print "\r\n"
            client.print response 
          else
            client.print "Expires: -1\r\n"
            client.print "\r\n"
            begin
              my_session=client.peeraddr[1]
              if not @http_sessions[my_session]
                #puts "**************** new port #{my_session}"
                @http_sessions[my_session]={client_port:client.peeraddr[1],client_ip:client.peeraddr[2] , log_position:0 }
              end
              my_event=0
              loop do
                begin
                  type,response=eval "json_#{act} request,my_session,my_event"
                  my_event+=1
                rescue => e
                  puts "**** AJAX EXEC #{fn} failed:  #{e}"
                  puts "#{e.backtrace[0..2]}"
                  pp e.backtrace
                  response=[{act: :error, msg:"Error executing JSON",alert: "Syntax error '#{e}' in '#{fn}'"}].to_json
                end 
                if not response or response==[] or response=={}
                else
                  client.print  "retry: 1000\n"
                  client.print  "data: #{response.to_json}\n\n"
                end
                sleep 1
                break if my_event>100
              end
            rescue => e
              puts "stream #{client} died #{e}"
              pp e.backtrace
            end

          end
          client.close
        rescue Exception =>e
          puts "http thread died #{e}"
          pp e.backtrace
          client.print "Error #{e}"
          client.close
        end
      end
    end
  end
end
