$: << "." << "lib"

require 'rubygems'
require 'bundler/setup'
require 'eventmachine'
require 'em-mongo'
require 'json'
require 'logger'
require 'em-zeromq'

MONGODB_HOST = "localhost"
MONGODB_DATABASE = "tweetflow"

ONE_GB = 1048576000
HUNDRED_MB = 104857600
TEN_MB = 10485760

@logger = Logger.new(File.expand_path("./log/tweetflow.log"))

class TweetHandler
  attr_reader :logger
  def initialize(logger)
    @logger = logger
    db.create_collection("tweets")
    db.command({"convertToCapped" => "tweets", "size" => ONE_GB})
    collection.create_index([["coordinates.coordinates", EM::Mongo::GEO2D]])    
  end
  
  def db
    @db ||= EM::Mongo::Connection.new(MONGODB_HOST).db(MONGODB_DATABASE)
  end
  
  def collection
    @coll ||= db.collection("tweets")
  end
  
  def on_readable(socket, messages)
    messages.each do |message|
      tweet = JSON.parse(message.copy_out_string)
      collection.insert(tweet)
      message.close
    end
  end
end

path = File.expand_path(File.join(File.expand_path(__FILE__), "..", "..", "tmp", "tweetflow.sock"))  

context = EM::ZeroMQ::Context.new(1)
  
EM.run do
  
  @logger.info("Starting")
  
  socket = context.connect(ZMQ::SUB, "ipc://#{path}", TweetHandler.new(@logger))
  socket.subscribe("")
  
  Signal.trap("INT")  { @logger.info("Caught INT, exiting"); socket.unbind; EM.stop }
  Signal.trap("TERM") { @logger.info("Caught TERM, exiting"); socket.unbind; EM.stop }
end