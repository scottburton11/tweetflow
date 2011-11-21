require 'json'

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
