#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'rubygems'
require 'open-uri'
require 'uri'
require 'sqlite3'
require 'twitter'
require 'bitly'
require 'syslog'
require 'nokogiri'

require_relative 'transmission-client'
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
  def initialize(shows, download_dir)
    @download_dir = download_dir
    @shows = shows

    @client = Transmission::Client.new(Settings::TRANSMISSION_SERVER)
    @client.start_server_if_not_running(Settings::TRANSMISSION_COMMAND)

    base_dir = File.dirname(__FILE__)
    @db = SQLite3::Database.new("#{base_dir}/torrentFeedLoader.sqlite3")
  end

  # iterate over the feed items and fetch them
  def visit_shows
    log("fetching current eztv content")
    html = Nokogiri::HTML(open("http://eztv.it"))
    rows = html.xpath("//tr[@class='forum_header_border']")
    rows.each do |row|
      rowdoc = Nokogiri::HTML(row.to_s)
      name = rowdoc.xpath("//a[@class='epinfo']").text
      magnet = rowdoc.xpath("//a[@class='magnet']")[0]['href']

      @shows.each do |show|
        if name =~ show[:feed_pattern]
          log("'#{name}' at '#{magnet}>'")
          download_magnet(magnet) unless loadedBefore?(magnet)
        end
      end
    end
  end

  # download the given torrent via btpd
  def download_magnet(magnet)
    id = @client.add(magnet, @download_dir)
    log("downloading torrent #{magnet} (##{id})")
  rescue Exception => ex
    log("unable to load torrent #{magnet}: #{ex}")
  end

  # send a tweet with a link to each file in the given array
  def tweet_new_files
    Bitly.use_api_version_3
    bitly = Bitly.new(Settings::BITLY_USERNAME,
                      Settings::BITLY_API_KEY)

    # search for new downloaded files
    new_files = []
    @db.execute('create table if not exists tweets(tweet varchar primary key);')
    Dir.entries(download_dir).each do |filename|
      next if ['.', '..'].include?(filename) or filename =~ /\.part$/
      begin
        @db.execute("insert into tweets values('#{filename}');")
        new_files << filename
      rescue
      end
    end

    # then tweet the files found
    new_files.each do |file|
      url = "#{Settings::BASE_URL}/#{file}"
      short_url = bitly.shorten(url).short_url
      tweet = "#{file[0...50]}: #{short_url} (#{Time.now.to_i})"
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

  # search all feeds for new torrents
  shows = Settings::SHOWS || raise('no shows configured!')
  fl = FeedMonitor.new(shows, download_dir)
  fl.visit_shows

  # check for torrents done downloading and tweet them
  client = Transmission::Client.new(Settings::TRANSMISSION_SERVER)
  if client.is_running?
    client.remove_finished_torrents
    client.shutdown if client.list == []
  end

  # search for new downloaded torrents to be tweeted
  fl = FeedMonitor.new(nil, download_dir)
  fl.tweet_new_files
end
