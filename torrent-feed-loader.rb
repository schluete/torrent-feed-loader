#!/usr/bin/env ruby

require 'rubygems'
require 'simple-rss'
require 'open-uri'
require 'uri'
require 'sqlite3'


class FeedMonitor
  attr_accessor :feedUrl

  # constructor, get the feed content
  def initialize(feedUrl)
    @feedUrl = feedUrl
    @rss = SimpleRSS.parse(open(@feedUrl))
    @db = SQLite3::Database.new('torrent-feed-loader.sqlite3')
  end

  # iterate over the feed items and fetch them
  def visit_feed
    @rss.items.each do |item|
      unless loadedBefore?(item.link)
        url = URI.encode(item.link, '[]')
        torrent = open(url).read()
        filename = "torrents/#{item.link.split('/')[-1]}"
        open(filename, 'w+') { |fh| fh.write(torrent) }
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
end

feedUrl = 'http://your.torrent.feed/url.rss'
fl = FeedMonitor.new(feedUrl)
fl.visit_feed
