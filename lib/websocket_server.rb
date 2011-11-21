$: << "." << "lib"

require 'rubygems'
require 'bundler/setup'
require 'eventmachine'
require 'em-websocket'
require 'em-http-request'
require 'em-http/middleware/oauth'
require 'em-mongo'
require 'em-zeromq'
require 'json'
require 'logger'
require 'tweet'


MONGODB_HOST = "localhost"
MONGODB_DATABASE = "tweetflow"

path = File.expand_path(File.join(File.expand_path(__FILE__), "..", "..", "tmp", "tweetflow.sock"))  

context = EM::ZeroMQ::Context.new(1)

@logger = Logger.new(File.expand_path("./log/twitstream.log"))

class TweetHandler
  attr_reader :logger
  def initialize(logger, channel)
    @logger = logger
    @channel = channel
  end
    
  def on_readable(socket, messages)
    messages.each do |message|
      tweet = JSON.parse(message.copy_out_string)
      @channel.push tweet
      message.close
    end
  end
end



EM.run do
  channel = EM::Channel.new
  socket = context.connect(ZMQ::SUB, "ipc://#{path}", TweetHandler.new(@logger, channel))
  socket.subscribe("")
  
  collection = EM::Mongo::Connection.new(MONGODB_HOST).db(MONGODB_DATABASE).collection("tweets")
  
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
          collection.find({"coordinates.coordinates" => {"$within" => {"$box" => tbounds}}}).limit(limit).each do |doc|
            if doc
              tweet = Tweet.new(doc)
              ws.send(tweet.to_json) if tweet.coordinates && tweet.point?
            end
          end
        end

        sid = channel.subscribe do |json|
          EM.next_tick do
            tweet = Tweet.new(json)
            ws.send tweet.to_json if tweet.locatable? && tweet.within?(bounds)
          end
        end
      end
      ws.onclose do
        channel.unsubscribe(sid)
      end
    end
  end

  Signal.trap("INT")  { @logger.info("Caught INT, exiting"); socket.unbind; EM.stop }
  Signal.trap("TERM") { @logger.info("Caught TERM, exiting"); socket.unbind; EM.stop }
end