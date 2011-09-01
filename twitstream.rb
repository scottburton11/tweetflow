require 'rubygems'
require 'bundler/setup'
require 'eventmachine'
require 'em-websocket'
require 'em-http-request'
require 'em-http/middleware/oauth'
require 'em-mongo'
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

stream_uri = "http://stream.twitter.com/1/statuses/filter.json"

MONGODB_HOST = "localhost"
MONGODB_DATABASE = "twitstream"

HUNDRED_MB = 104857600
TEN_MB = 10485760

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

@logger = Logger.new("twitstream.log")

# Just track the #houcodecamp hashtag
# 
#body = {:track => "#houcodecamp" }

class Tweet

  attr_reader :data
  def initialize(hash)
    @data = hash
  end

  def to_json(*args)
    data.to_json(*args)
  end

  def locatable?
    coordinates && point?
  end

  def location
    data['coordinates']
  end

  def coordinates
    location && location['coordinates']
  end

  def point?
    location['type'] == "Point"
  end

  def latitude
    coordinates[1].to_f
  end

  def longitude
    coordinates[0].to_f
  end

  def within?(bounds)
    return false unless bounds.all?
    latitude > bounds[0] && longitude > bounds[1] && latitude < bounds[2] && longitude < bounds[3] rescue false
  end

  def to_json(options={})
    {:text => data['text'], :coordinates => data['coordinates'], :user => data['user'], :id => data['id']}.to_json(options)
  end
end

################# 
# Main Run Loop #
#################

EM.run do
  @logger.info("Starting run loop")

  request = EventMachine::HttpRequest.new(stream_uri)
  request.use EventMachine::Middleware::OAuth, OAuthConfig
  http = request.post(:body => body, :head => {"Content-Type" => "application/x-www-form-urlencoded"})

  channel = EM::Channel.new

  buffer = ""
  
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
      channel.push(Tweet.new(JSON.parse(line)))
    end
  }

  db = EM::Mongo::Connection.new(MONGODB_HOST).db(MONGODB_DATABASE)
  coll = db.collection("tweets")
  db.command({"convertToCapped" => "tweets", "size" => TEN_MB})
  coll.create_index([["coordinates.coordinates", EM::Mongo::GEO2D]])


  msid = channel.subscribe do |tweet|
    coll.insert(tweet.data)
  end

  EM::WebSocket.start(:host => "0.0.0.0", :port => "8080") do |ws|
    ws.onopen do
      sid = nil

      ws.onmessage do |msg|
        @logger.info msg
        params = JSON.parse(msg)
        channel.unsubscribe(sid) if sid
        bounds = params['bounds']
        tbounds = [[bounds[1], bounds[0]], [bounds[3], bounds[2]]]
        limit = params['limit']
        if limit.kind_of?(Numeric) && limit > 0
          coll.find({"coordinates.coordinates" => {"$within" => {"$box" => tbounds}}}).limit(limit).each do |doc|
            if doc
              tweet = Tweet.new(doc)
              ws.send(tweet.to_json) if tweet.coordinates && tweet.point?
            end
          end
        end


        sid = channel.subscribe do |tweet|
          EM.next_tick do
            ws.send tweet.to_json if tweet.locatable? && tweet.within?(bounds)
          end
        end
      end
      ws.onclose do
        channel.unsubscribe(sid)
      end
    end
  end

  Signal.trap("INT")  { @logger.info("Caught INT, exiting"); http.unbind;  EM.stop }
  Signal.trap("TERM") { @logger.info("Caught TERM, exiting"); http.unbind;  EM.stop }
end
