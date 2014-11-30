Gem::Specification.new do |s|
  s.name        = 'mqtt-sn-ruby'
  s.version     = '0.1.8'
  s.date        = '2014-11-29'
  s.summary     = "Ruby toolkit for MQTT-SN"
  s.description = "Ruby toolkit for MQTT-SN, compatible with RSMB, command line tools and API"
  s.authors     = ["Ari Siitonen"]
  s.email       = 'jalopuuverstas@gmail.com'
  s.files       = ["lib/mqtt-sn-ruby.rb","lib/mqtt-sn-http.rb", "examples/send.rb", "examples/recv.rb","c/mqtt-sn.c","c/mqtt-sn.h","c/mqtt-sn-pub.c"]
  s.files      += Dir['http/**/*']
  s.executables << 'mqtt-sn-pub.rb'
  s.executables << 'mqtt-sn-sub.rb'
  s.executables << 'mqtt-sn-forwarder.rb'
  s.homepage    = 'https://github.com/arisi/mqtt-sn-ruby'
  s.license     = 'MIT'
end