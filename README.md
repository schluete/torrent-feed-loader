torrentFeedLoader
===================

simple collection scripts to monitor a torrent RSS feed as a cronjob, then
download the new torrents from the feed and finally present them an a feed
for the media software of your choice, e.g. iTunes.


Installation and Usage
----------------------

* you'll need to have a running (daemon) version of the transmission
  torrent client.
* copy the <code>settings.rb</code> example file and modify it according
  to your needs, esp. the command to start the transmission server
* finally run the main executable via a cronjob every few hours:
      # ./torrentFeedLoader.rb
* the logging output gets written into the system log, e.g. <code>/var/log/messages</code>
