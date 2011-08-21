require 'rubygems'
require 'bundler/setup'
require 'eventmachine'
require 'em-websocket'
require 'em-http-request'
require 'em-http/middleware/oauth'


################# 
# Configuration #
#################

OAuthConfig = {
 :consumer_key        => ENV['API_KEY'],
 :consumer_secret     => ENV['API_SECRET'],
 :access_token        => ENV['TOKEN_KEY'],
 :access_token_secret => ENV['TOKEN_SECRET']
}

stream_uri = "http://stream.twitter.com/1/statuses/filter.json"

# Four geographic US areas
# 
# locs = {
#   :austin        => [-99.30126953125,     29.72202143146981,  -96.285522460937,    30.843852348622054],
#   :houston       => [-97.12322988437501,  28.653810936810142, -94.31072988437501,  30.894538388135828],
#   :california    => [-123.57830800937501, 32.40749516414054,  -111.51531972812501, 39.529972085084445],
#   :ny            => [-78.57281484531256,  40.72694242903686,  -72.54132070468756,  42.6667626685163]
# }
#body = {:locations => locs.inject([]){|array, pair| pair[1].each {|c| array << c } ; array  }.join(",") }

# All of US and EU
# 
us = [-143.97991933750006, 19.390800025582905, -47.476013087500064, 60.15071794869914]
eu = [-25.942809962500064, 30.132630020114565, 43.754455662499936,  58.301896604717285]
body = {:locations => (us + eu).join(",") }

# Just track the #houcodecamp hashtag
# 
#body = {:track => "#houcodecamp" }

################# 
# Main Run Loop #
#################

EM.run do

  request = EventMachine::HttpRequest.new(stream_uri)
  request.use EventMachine::Middleware::OAuth, OAuthConfig
  http = request.post(:body => body, :head => {"Content-Type" => "application/x-www-form-urlencoded"})

  channel = EM::Channel.new

  buffer = ""
  
  http.stream {|chunk|
    if chunk =~ /Error 401 UNAUTHORIZED/
      puts chunk
      http.unbind
      EM.stop
    end
    buffer << chunk
    while line = buffer.slice!(/(.*)\r\n/) do
      channel.push(line)
    end
  }

  EM::WebSocket.start(:host => "0.0.0.0", :port => "8080") do |ws|

    sid = nil

    ws.onopen do
      ws.onmessage do |msg|
        puts msg
      end
      ws.onclose do
        channel.unsubscribe(sid)
      end
      sid = channel.subscribe do |msg|
        EM.next_tick do
          ws.send msg
        end
      end
    end
  end

  Signal.trap("INT")  { http.unbind; channel.unsubscribe(sid) if sid; EM.stop }
  Signal.trap("TERM") { http.unbind; channel.unsubscribe(sid) if sid; EM.stop }
end