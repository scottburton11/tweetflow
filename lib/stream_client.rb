require 'rubygems'
require 'bundler/setup'
require 'eventmachine'
require 'em-http-request'
require 'em-http/middleware/oauth'
require 'em-zeromq'
require 'json'
require 'logger'

################# 
# Configuration #
#################

OAuthConfig = {
 :consumer_key        => ENV['API_KEY'],
 :consumer_secret     => ENV['API_SECRET'],
 :access_token        => ENV['TOKEN_KEY'],
 :access_token_secret => ENV['TOKEN_SECRET']
}

stream_uri = "https://stream.twitter.com/1/statuses/filter.json"

# Four geographic US areas
# 
# locs = {
#   :austin        => [-99.30126953125,     29.72202143146981,  -96.285522460937,    30.843852348622054],
#   :houston       => [-97.12322988437501,  28.653810936810142, -94.31072988437501,  30.894538388135828],
#   :california    => [-123.57830800937501, 32.40749516414054,  -111.51531972812501, 39.529972085084445],
#   :ny            => [-78.57281484531256,  40.72694242903686,  -72.54132070468756,  42.6667626685163]
# }
#body = {:locations => locs.inject([]){|array, pair| pair[1].each {|c| array << c } ; array  }.join(",") }

# Coordinate sets, in Twitter order
us = [-143.97991933750006, 19.390800025582905, -47.476013087500064, 60.15071794869914]
eu = [-25.942809962500064, 30.132630020114565, 43.754455662499936,  58.301896604717285]
africa = [-25.635192775000064, -37.24183333529351, 64.36480722499994, 37.2188216841927]
south_asia =[21.386291599999936, -11.02008907935313, 111.38629159999994, 56.7447993643333]
asia = [85.63433847499994, -21.71169169171561, 175.63433847499994, 50.11131175752551]
south_pacific = [96.26910409999994, -51.681515962670716, -173.73089590000006, 19.38043655632485]
hawaii = [-163.42572011875006, 15.005117430141318, -152.17572011875006, 24.443995739883658]
south_america = [-111.38348379062506, -56.2513788813518, -21.383483790625064, 11.896213541337962]
body = {:locations => (us + eu + asia + south_asia + south_pacific + hawaii + south_america).join(",") }

@logger = Logger.new(File.expand_path("./log/tweetflow.log"))

module Publisher
  def on_writable
    @logger.info("Ready for writing")
  end
end

EM.run do
  @logger.info("Starting run loop")

  request = EventMachine::HttpRequest.new(stream_uri)
  request.use EventMachine::Middleware::OAuth, OAuthConfig
  http = request.post(:body => body, :head => {"Content-Type" => "application/x-www-form-urlencoded"})

  path = File.expand_path(File.join(File.expand_path(__FILE__), "..", "..", "tmp", "tweetflow.sock"))
  
  buffer = ""
  
  context = EM::ZeroMQ::Context.new(1)
  
  puts "ipc://#{path}"
  socket = context.bind(ZMQ::PUB, "ipc://#{path}", Publisher)
  
  http.stream {|chunk|
    if chunk =~ /Error 401 UNAUTHORIZED/
      @logger.warn chunk
      http.unbind
      EM.stop
      @logger.warn "Error, exiting"
      exit(false)
    end
    
    buffer << chunk
    
    while line = buffer.slice!(/(.*)\r\n/) do
      socket.send_msg line      
    end
  }
  
  
  Signal.trap("INT")  { @logger.info("Caught INT, exiting"); http.unbind; socket.unbind; EM.stop }
  Signal.trap("TERM") { @logger.info("Caught TERM, exiting"); http.unbind;  socket.unbind; EM.stop }
end