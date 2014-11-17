Gem::Specification.new do |s|
  s.name        = 'mqtt-sn-ruby'
  s.version     = '0.0.4'
  s.date        = '2014-11-17'
  s.summary     = "Ruby toolkit for MQTT-SN"
  s.description = "Ruby toolkit for MQTT-SN, compatible with RSMB, command line tools and API"
  s.authors     = ["Ari Siitonen"]
  s.email       = 'jalopuuverstas@gmail.com'
  s.files       = ["lib/mqtt-sn-ruby.rb", "test.rb"]
  s.executables << 'mqtt-sn-pub.rb'
  s.executables << 'mqtt-sn-sub.rb'
  s.homepage    = 'https://github.com/arisi/mqtt-sn-ruby'
  s.license     = 'MIT'
end