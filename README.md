torrentFeedLoader
===================

simple collection scripts to monitor a torrent RSS feed as a cronjob, then
download the new torrents from the feed and finally present them an a feed
for the media software of your choice, e.g. iTunes.


Installation and Usage
----------------------

* you'll need to compile a version for the btpd torrent client. For easy compilation
  the client is referenced as a git submodule in this repository, so you'll have
  to initialize the module after cloning this repository:
      # git submodule update --init btpd

* then use the automake facilities to build the btpd client:
      # cd btpd
      # aclocal 
      # autoconf
      # automake -ac
      # ./configure
      # make

* copy at least the executable into the <code>bin<code> folder in the repository root:
      # cp ./btpd/btpd ../bin 
      # cp ./cli/btcli ../bin 
      # cp ./cli/btinfo ../bin

* finally copy the <code>settings.rb</code> example file and modify it according to your needs,
  then run the main executable:
      # ./torrentFeedLoader.rb
  
* the logging output gets written into the system log, e.g. <code>/var/log/messages</code>
