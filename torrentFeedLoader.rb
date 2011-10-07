#!/usr/bin/env ruby

require 'rubygems'
require 'open-uri'
require 'uri'
require 'sqlite3'
require 'twitter'
require 'bitly'
require 'syslog'
require 'nokogiri'

require_relative 'btpd-client'
require_relative 'settings'


# regular expression to filter the torrent URLs from the tweets
URL_REGEX = /((http|https):\/\/[a-z0-9]+([\-\.]{1}[a-z0-9]+)*\.[a-z]{2,5}((:[0-9]{1,5})?\/[^\s]*)?)/ix


# the current URI module has a bug. It can't handle square brackets
# in URL, although that's perfectly legal. We're monkey-patching the
# class a little bit until the bug gets fixed in the official version.
module URI
  class << self
    def parse_with_safety(uri)
      parse_without_safety(uri.gsub('[', '%5B')
                              .gsub(']', '%5D'))
    rescue
      parse_without_safety(uri)
    end
    alias parse_without_safety parse
    alias parse parse_with_safety
  end
end


class FeedMonitor
  attr_reader :twitter_username
  attr_reader :shows
  attr_reader :download_dir

  # constructor, get the feed content
  def initialize(twitter_username, shows, download_dir)
    @download_dir = download_dir
    @twitter_username = twitter_username
    @shows = shows

    base_dir = File.dirname(__FILE__)
    @db = SQLite3::Database.new("#{base_dir}/torrentFeedLoader.sqlite3")
  end

  # iterate over the feed items and fetch them
  def visit_feed
    log("visiting tweets of #{@twitter_username}")
    Twitter.user_timeline(@twitter_username, :count=>100).each do |tweet|
      @shows.each do |show|
        if tweet.text =~ show and tweet.text =~ URL_REGEX
          url = $1
          log("'#{tweet.text}' at <#{url}>")
          download_torrent(url) unless loadedBefore?(url)
        end
      end
    end
  end

  # download the given torrent via btpd
  def download_torrent(url)
    # first download the torrent file itself
    torrent = open(url).read()
    dir_before = Dir.entries(@download_dir)

    # then start the torrent client and start the download
    bc = Btpd::Client.new()
    bc.start_server_if_not_running
    id = bc.add("t#{Time.now.to_i}", torrent, @download_dir)
    bc.start(id)
    log("downloading torrent #{url} (##{id})")

    # let's wait until the torrent is fully downloaded
    while true
      torrents = bc.tget([Btpd::TVAL_NUM, Btpd::TVAL_STATE])
      (bc.die! ; break) if torrents.size == 0

      torrents.each do |(num, state)|
        bc.del(num) if state == Btpd::TSTATE_SEED
      end
      sleep(10)
    end

    # then send out a tweet about the new download
    dir_after = Dir.entries(@download_dir)
    new_files = dir_after - dir_before
    tweet_files(new_files)
  rescue Exception => ex
    log("unable to load torrent #{url}: #{ex}")
  end

  # send a tweet with a link to each file in the given array
  def tweet_files(new_files)
    Bitly.use_api_version_3
    bitly = Bitly.new(Settings::BITLY_USERNAME,
                      Settings::BITLY_API_KEY)

    new_files.each do |file|
      url = "#{Settings::BASE_URL}/#{file}"
      short_url = bitly.shorten(url).short_url
      tweet = "#{file}: #{short_url} (#{Time.now.to_i})"
      begin
        Twitter.update(tweet)
        log("tweet #{tweet}")
      rescue
        log("unable to send tweet #{tweet}")
      end
    end
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

  # helper method, write a message to the system log
  def log(msg)
    Syslog.open($0, Syslog::LOG_PID | Syslog::LOG_CONS) { |log| log.warning("#{msg.gsub('%', '%%')}") }
  end
end


# main program
if __FILE__ == $0
  Twitter.configure do |config|
    config.consumer_key = Settings::TWITTER_CONSUMER_KEY
    config.consumer_secret = Settings::TWITTER_CONSUMER_SECRET
    config.oauth_token = Settings::TWITTER_OAUTH_TOKEN
    config.oauth_token_secret = Settings::TWITTER_OAUTH_SECRET
  end

  download_dir = Settings::DOWNLOAD_DIR || raise('no download directory configuration!')
  Dir.mkdir(download_dir) unless File.directory?(download_dir)

  feeds = Settings::FEEDS || raise('no torrent feed configuration!')
  feeds.each do |twitter_username, shows|
    fl = FeedMonitor.new(twitter_username, shows, download_dir)
    fl.visit_feed
  end
end
