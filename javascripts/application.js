var lastOpened = null;
var WEBSOCKET_HOST = "tweetflow.info";
var MAX_TWEETS = 30;

var infoTemplate = "<div class='tweet-bubble'><img src='<%= user.profile_image_url %>' alt='<%= user.username %>' align='left'/><div><strong><%= user.name %></strong><div><%= text %></div></div></div>";
var tweetTemplate = "<div class='img-col'><img src='<%= user.profile_image_url %>'/></div><div class='tweet-col'><strong><%= user.screen_name %></strong>&nbsp;<%= text %></div><div class='clear'></div>"

// Define a custom marker, if you choose.
// var markerSize = new google.maps.Size(562, 352, "px", "px");
// var scaledSize = new google.maps.Size(24, 24, "px", "px");
// var anchor     = new google.maps.Point(281, 352);
// var origin     = new google.maps.Point(0, 0);
// var markerImage = new google.maps.MarkerImage("http://cdn1.iconfinder.com/data/icons/aquaticus/60%20X%2060/twitter.png", null, null, null, scaledSize);

var Tweet = Backbone.Model.extend({
  
  position: function(){
    return new google.maps.LatLng(this.get("latlng").coordinates[1], this.get("latlng").coordinates[0]);
  }
  
});

var Tweets = Backbone.Collection.extend({
  model: Tweet
});

var TweetView = Backbone.View.extend({
  
  tagName: "li",
  
  className: "tweet",
  
  initialize: function(){
    _.bindAll(this, "render", "remove", "placeMarker", "showInfoWindow");
    this.model.bind("change", this.render);
    this.model.bind("remove", this.remove);
    this.template = _.template(tweetTemplate);
    this.infoTemplate = _.template(infoTemplate);
  },
  
  render: function(){
    $(this.el).html(this.template(this.model.toJSON()));
    var $this = this;
    $(this.el).click(function(){$this.showInfoWindow()});
    return this;
  },
  
  remove: function(){
    window.lastView = this;
    $(this.el).remove();
    google.maps.event.clearListeners(this.marker);
    this.marker.setMap(null);
    this.infoWindow.close();
  },
  
  placeMarker: function(map) {
    this.marker = new google.maps.Marker({
      position: this.model.position(),
      map: map
    });

    this.infoWindow = new google.maps.InfoWindow({
      content: this.infoTemplate(this.model.toJSON())
    });

    google.maps.event.addListener(this.marker, "click", this.showInfoWindow);
    return this.marker
  }, 
  
  showInfoWindow: function(){
    if (lastOpened != null) {
      lastOpened.close();
    };
    this.infoWindow.open(window.map, this.marker);
    window.map.panTo(this.marker.getPosition());
    lastOpened = this.infoWindow;
  }
});

var TweetsView = Backbone.View.extend({
  el: "#tweetbar",
  initialize: function() {
    _.bindAll(this, "render", "renderTweet");
    this.collection.bind("add", this.renderTweet);
  },
  
  renderTweet: function(tweet){
    var tweetView = new TweetView({
      model: tweet
    });
    $("#tweetbar").prepend(tweetView.render().el);
    tweetView.placeMarker(map);
  }
});

tweets = new Tweets();

tweets.bind("add", function(tweet){
  if (tweets.length > MAX_TWEETS) {
    tweets.remove(tweets.first());
  };
});

function addTweet(json) {
  var tweet = new Tweet({
    text: json.text,
    latlng: json.coordinates,
    user: json.user,
    id: json.id
  });

  var included = tweets.detect(function(tweet) { return tweet.id === json.id });
  if (!included) {
    tweets.add(tweet);
  }
};

function cleanUpTweets() {
  var remove_tweets = tweets.reject(function(tweet) { 
    return withinMapView(tweet.get("latlng").coordinates);
  });
  tweets.remove(remove_tweets);
}

window.mapMoveTimeout = null;

function handleMapMove(){
  setWindowBounds();
  if (window.mapMoveTimeout !== null) {
    window.clearTimeout(window.mapMoveTimeout);
  }
  cleanUp();
}

function cleanUp() {
  window.mapMoveTimeout = window.setTimeout(function(){
    cleanUpTweets();
    requestTweets();
    window.mapMoveTimeout = null;
  }, 800);
}

function requestTweets(){
  //window.ws.send(window.map.getBounds());
  var request = {
    bounds: [window.slat, window.wlng, window.nlat, window.elng],
    limit: MAX_TWEETS - tweets.length
  }
  window.ws.send(JSON.stringify(request));
}

function setWindowBounds () {
  var bounds = map.getBounds()
  window.slat = bounds.getSouthWest().lat();
  window.wlng = bounds.getSouthWest().lng();
  window.nlat = bounds.getNorthEast().lat();
  window.elng = bounds.getNorthEast().lng();
}

function withinMapView(coordinates) {
  if (coordinates[1] > window.slat && coordinates[1] < window.nlat && coordinates[0] > window.wlng && coordinates[0] < window.elng) {
    return true
  } else {
    return false
  };
};

function websocket_instance(host) {
  if (window.hasOwnProperty("MozWebSocket")) {
    return new MozWebSocket(host);
  } else if (window.hasOwnProperty("WebSocket")){
    return new WebSocket(host);
  };
}

function initiateWebSocket() {
  var ws = websocket_instance("ws://"+WEBSOCKET_HOST+":8080")

  ws.onopen = function(){
    setWindowBounds();
    requestTweets();
    google.maps.event.addListener(window.map, "idle", handleMapMove);
  }

  ws.onmessage = function(msg) {
    var json = JSON.parse(msg.data);
    addTweet(json);
  };

  return ws;
}

function browserSupported() {
  return Modernizr.websockets
}

function dissapointUser() {
  var msg = "Sorry, TweetFlow doesn't support your browser."
  console.log(msg)
}

function bootstrap() {

  // if (Modernizr.geolocation) {
  //   geolocate();
  // } else {
  //   startTweetFlow();
  // };

  startTweetFlow();
  
  window.tweetsView = new TweetsView({
    collection: tweets
  });
}

function geolocate(){
  navigator.geolocation.getCurrentPosition(
    function(position) {
      navigateToCoordinates([position.coords.latitude, position.coords.longitude]);
    },
    function(error) {
      startTweetFlow();
    }
  );
}

function assignWebSocket() {
  window.ws = initiateWebSocket();
}

function startTweetFlow(callback){
  loaded_event = google.maps.event.addListener(window.map, "tilesloaded", function(){
    console.log("Loaded");
    google.maps.event.removeListener(loaded_event);
    if (callback && typeof(callback) === "function") {
      callback.call();
    };
    assignWebSocket();
  });
}

function stopTweetFlow(){
  window.ws.close();
}

function navigateClick(event){
  var city = $(event.target).attr("data-location");
  if (!(city === undefined)) {
    var coordinates = coordinatesList[city];
    navigateToCoordinates(coordinates);    
  }
};

var coordinatesList = {
  "los-angeles": [33.77740919605361, -117.95605459140626],
  "houston": [29.670128669804495, -95.37640371250001],
  "seattle": [47.59155698249811, -122.29290761875001],
  "maui": [20.790753080390292, -156.34915151523438],
  "tokyo": [35.7041217738303, -220.21130361484379],
  "hong-kong": [22.440196733153556, -245.82318105625004],
  "new-york": [40.792735274749475, -73.89263906406254],
  "london": [51.504449194741255, -0.12905874179691246]
}

function navigateToCoordinates(coordinates) {
  stopTweetFlow();
  var latLng = new google.maps.LatLng(coordinates[0], coordinates[1]);
  window.map.setZoom(10);
  window.map.panTo(latLng);
  
  startTweetFlow(handleMapMove)
}

function handleNavClick(event) {
  $("ul#nav li").removeClass("active");
  $(this).addClass("active");
  navigateClick(event);
}

$(function(){
  window.map = new google.maps.Map(document.getElementById("map"), {
    center: new google.maps.LatLng(30.284540, -97.7933959),
    zoom: 4,
    mapTypeId: google.maps.MapTypeId.ROADMAP
  });

  if (browserSupported()) {
    // startTweetFlow();
    bootstrap();
  } else {
    dissapointUser();
  };
  
  $("ul#nav").on("click", "li", handleNavClick)
  
});