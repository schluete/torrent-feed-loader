#!/usr/bin/env ruby

require 'rubygems'
require 'simple-rss'
require 'open-uri'
require 'uri'
require 'sqlite3'


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

base_dir = File.dirname(__FILE__)
feed_url = IO.read('doc/rss-feed-link.url')
fl = FeedMonitor.new(feed_url, base_dir)
fl.visit_feed
