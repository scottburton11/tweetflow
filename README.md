Twitstream
==========
A sample application that visualizes the Twitter stream using EventMachine, WebSockets, Google Maps, Backbone.js and oh, what the hell, MongoDB. 

_(Just kidding, no MongoDB)_

Why?
----
This is mostly a proof-of-concept application to see how well these technologies would go together. Turns out they're a compelling mix. I presented this at Houston Code Camp 2011.

Getting Started
---------------
Clone the repo and `bundle install`.

If you haven't yet, create a Twitter application on [Twitter's developer site]("https://dev.twitter.com/"), and take a good look at the [API docs]("https://dev.twitter.com/docs"), particularly the [section on the Streaming API]("https://dev.twitter.com/docs/streaming-api"). 

Export your consumer key, consumer secret, access token and access token secret as environmental variables `API_KEY`, `API_SECRET`, `TOKEN_KEY` and `TOKEN_SECRET`. 

Run the server with `ruby twitstream.rb`, and copy `index.html`, `/javascripts` and `/stylesheets` to a webserver-accessible location.

Warnings
--------
  * There's no evidence that these concepts are ready for production use. 
  * Use at your own risk, and stress-test for reliability and resource usage. 
  * Don't consume more than one Twitter stream via HTTP.
  * Eat your vegetables, and call your Mother. She's worried about you.
  
Errata
------
The most recent OAuth gem isn't compatible with the latest few commits of em-http-request, so the commit used here 339e5e5 includes a patch. See https://github.com/igrigorik/em-http-request/issues/87 for details.

Follow me at @scottburton

License
-------
This software is available via the MIT License, and is copyright 2011 by Scott Burton.