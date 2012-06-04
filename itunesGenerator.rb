#!/usr/bin/env ruby

require 'rubygems'
require 'erb'
require 'ostruct'
require 'syslog'

require_relative 'settings'


class RssGenerator
  attr_reader :channel
  attr_reader :content

  def initialize(download_dir, output_dir, base_url, channel)
    @download_dir = download_dir
    @output_dir = output_dir
    @base_url = base_url
    @channel = channel
  end

  def generate_rss_file
    # build the list of files to include in the podcast feed
    files = []
    Dir.foreach(@download_dir) do |filename|
      if filename =~ @channel[:filename_pattern]
        created_at  = File.ctime(@download_dir + '/' + filename)
        files << OpenStruct.new({
            :url => "#{@base_url}/#{filename}",
            :title => $1.gsub('.', ' '),
            :length => File.size?(@download_dir + '/' + filename),
            :created_at => created_at,
            :pubDate => created_at.strftime('%a, %d %b %Y %H:%M:%S %z')
        })
      end
    end
    @channel[:files] = files.sort { |a, b| b.created_at <=> a.created_at }

    # then generate the XML file
    template = IO.read('itunesGenerator.erb')
    namespace = OpenStruct.new(@channel)
    feedxml = ERB.new(template, 0, '%<>')
    result = feedxml.result(namespace.instance_eval { binding })

    # and write it to the output file
    filename = @channel[:title].gsub(' ', '') + '.rss'
    File.open("#{@output_dir}/#{filename}", 'w') do |file|
      file.write(result)
    end
    log("generated iTunes RSS feed '#{@channel[:title]}' with #{files.size} entries")
  end

  # helper method, write a message to the system log
  def log(msg)
    Syslog.open($0, Syslog::LOG_PID | Syslog::LOG_CONS) { |log| log.warning("#{msg.gsub('%', '%%')}") }
  end
end


# main program, update the RSS files for each feed
if __FILE__ == $0
  shows = Settings::SHOWS || raise('no shows configured!')
  shows.select { |s| s.include?(:title) }.each do |channel|
    rss = RssGenerator.new(Settings::DOWNLOAD_DIR, Settings::ITUNES_RSS_DIR, Settings::BASE_URL, channel)
    rss.generate_rss_file
  end
end
