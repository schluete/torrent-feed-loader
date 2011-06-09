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


class FeedMonitor
  attr_reader :feed
  attr_reader :download_dir

  # constructor, get the feed content
  def initialize(feed, download_dir)
    @download_dir = download_dir
    @feed = feed

    base_dir = File.dirname(__FILE__)
    @db = SQLite3::Database.new("#{base_dir}/torrentFeedLoader.sqlite3")
  end

  # iterate over the feed items and fetch them
  def visit_feed
    log("visiting feed #{@feed[:url]}")
    doc = Nokogiri::HTML(open(@feed[:url]))
    doc.css('tr.forum_header_border').each do |node|
      title_node = node.css('a.epinfo')[0]
      next unless title_node
      title = title_node[:title]
      url = node.css('a.download_1')[0][:href]
      download_torrent(url, title) unless loadedBefore?(url)
    end
  end

  # download the given torrent via btpd
  def download_torrent(url, title)
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
  feeds.each do |feed|
    fl = FeedMonitor.new(feed, download_dir)
    fl.visit_feed
  end
end
