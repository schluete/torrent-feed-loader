#!/usr/bin/env ruby

require 'rubygems'
require 'simple-rss'
require 'open-uri'
require 'uri'
require 'sqlite3'
require 'socket'
require 'bencode'


class TorrentClient
  attr_reader :socket_path
  @socket_path = ''

  attr_accessor :debug
  @debug = false

  TVAL_CGOT = 0      # bytes downloaded so far (NUM, bytes)
  TVAL_CSIZE = 1     # size of the complete file (NUM, bytes)
  TVAL_DIR = 2
  TVAL_NAME = 3      # name of the torrent file (STR, name)
  TVAL_NUM = 4       # internal index number of the torrent (NUM, number)
  TVAL_IHASH = 5
  TVAL_PCGOT = 6
  TVAL_PCOUNT = 7
  TVAL_PCCOUNT = 8
  TVAL_PCSEEN = 9
  TVAL_RATEDWN = 10  # current download rate
  TVAL_RATEUP = 11   # current upload rate
  TVAL_SESSDWN = 12  # number of bytes downloaded in the current session
  TVAL_SESSUP = 13   # number of bytes uploaded in the current session
  TVAL_STATE = 14    # status of the torrent (NUM, status)
  TVAL_TOTDWN = 15   # number of bytes totally downloaded so far
  TVAL_TOTUP = 16    # number of bytes totally uploaded so far
  TVAL_TRERR = 17
  TVAL_TRGOOD = 18
  TVAL_COUNT = 19

  
  # constructor
  def initialize(socket_path)
    @socket_path = socket_path
  end

  # initialize a server shutdown
  def die
    rc = execute_command(['die'])['code']
    raise "unable to shutdown server, result code #{rc}!" unless rc == 0
  end

  # set the upload/ download transfer rate limits in kbyte
  def rate(upload, download)
    rc = execute_command(['rate', upload * 1024, download * 1024])['code']
    raise "unable to set upload/download rate, result code #{rc}!" unless rc == 0
  end

  # stop all currently running torrent transfers
  def stop_all
    rc = execute_command(['stop-all'])['code']
    raise "unable to stop torrents, result code #{rc}!" unless rc == 0
  end

  # start a specific torrent. The parameter is either the 20-char
  # torrent hash value or numeric position from the tget output
  def start(hash_or_id)
    rc = execute_command(['start', hash_or_id])['code']
    raise "unable to start torrent '#{hash_or_id}', result code #{rc}!" unless rc == 0
  end

  # restart all previously stopped torrents
  def start_all
    rc = execute_command(['start-all'])['code']
    raise "unable to restart torrents, result code #{rc}!" unless rc == 0
  end

  # delete a given torrent
  def del(hash_or_id)
    rc = execute_command(['del', hash_or_id])['code']
    raise "unable to delete torrent, result code #{rc}!" unless rc == 0
  end

  # read information about the torrent from the server. The argument is a list
  # of TVAL_xxx field IDs to fetch. The resulting array will contain a list of
  # values the same order as the field list argument.
  def tget(fields)
    resp = execute_command(['tget', {
                              'from' => 0,  # query all torrents
                              'keys' => fields}])
    raise "unable to read server info, result code #{resp['code']}!" unless resp['code'] == 0

    # filter the type information from the results and return
    # the the values of the fields without its types
    resp['result'].map do |torrent|
      (0..torrent.length).step(2).map { |idx| torrent[idx + 1] }
    end
  end

  # add a new torrent to download. If the torrent was added successfully
  # the method returns the internal index of the torrent, otherwise an
  # exception gets thrown. IMPORTANT: the download directory argument must
  # be a fully qualified directory path!
  def add(torrent_name, torrent_data, download_dir)
    resp = execute_command(['add', {
                            'content' => download_dir,
                            'name' => torrent_name,
                            'torrent' => torrent_data}])
    raise "unable to add torrent, result code #{resp['code']}!" unless resp['code'] == 0
    resp['num']
  end
  

  # send a command to the btpd client and return its response
  def execute_command(cmd)
    # send the bencoded command string
    encoded = cmd.bencode()
    sock = UNIXSocket.open(@socket_path)
    sock.send([encoded.length].pack('L'), 0)
    sock.send(encoded, 0)
    puts "---> #{encoded}" if @debug

    # first get the length of the response
    len = sock.recvfrom(4)[0].unpack('L')[0]
    raise "communication error with btpd!" if not len or len == 0
    buffer = sock.recvfrom(len)[0]
    puts "<--- #{buffer}" if @debug
    sock.close

    # finally return the decoded bencode data
    BEncode.load(buffer)
  end
  private :execute_command

end

socket = '/home/schluete/.btpd/sock' 
tc = TorrentClient.new(socket)
#tc.die()
#tc.rate(100, 200)
#tc.start_all()
#tc.stop_all()
#tc.start(0)
#tc.start(1)

#tc.die()
#tc.del(0)
#tc.del(1)
tc.del(2)
tc.die()

#data = IO.read('./torrents/The.Daily.Show.2011.01.03.(HDTV-FQM)[VTV].torrent')
#num = tc.add('carcdr', data,
#             '/home/schluete/torrent-feed-loader/downloads')
#tc.start(num)
#puts "added torrent #{num}!"

torrents = tc.tget([TorrentClient::TVAL_CGOT,
                    TorrentClient::TVAL_CSIZE,
                    TorrentClient::TVAL_NUM,
                    TorrentClient::TVAL_NAME,
                    TorrentClient::TVAL_STATE])

states = ['inactive', 'starting', 'stopped', 'leeching', 'seeding']
torrents.each do |torrent|
  puts "%02d: %s %s (%d%%)" % [torrent[2],
                             torrent[3],
                             states[torrent[4]],
                             (torrent[0]/(torrent[1]/100.0)).round]
end

exit


class FeedMonitor
  attr_accessor :feed_url

  # constructor, get the feed content
  def initialize(feed_url, base_dir)
    @base_dir = base_dir
    @feed_url = feed_url
    @rss = SimpleRSS.parse(open(@feed_url))
    @db = SQLite3::Database.new("#{@base_dir}/torrent-feed-loader.sqlite3")
  end

  # iterate over the feed items and fetch them
  def visit_feed
    @rss.items.each do |item|
      unless loadedBefore?(item.link)
        url = URI.encode(item.link, '[]')
        torrent = open(url).read()
        filename = "#{@base_dir}/torrents/#{item.link.split('/')[-1]}"
        open(filename, 'w+') { |fh| fh.write(torrent) }
        download_torrent(filename)
      end
    end
  end

  # download the given torrent via btpd
  def download_torrent(filename)
  end

  # returns true if the given link was fetched before
  def loadedBefore?(link)
    creationQuery = <<-EOF
      create table if not exists links(
        link varchar primary key not null,
        created_at timestamp
      );
    EOF
    @db.execute(creationQuery)
    @db.execute("insert into links values('#{link}',datetime('now'));")
    false
  rescue
    true
  end
end

#base_dir = File.dirname(__FILE__)
#feed_url = IO.read('doc/rss-feed-link.url')
#fl = FeedMonitor.new(feed_url, base_dir)
#fl.visit_feed
