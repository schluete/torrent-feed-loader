#!/usr/bin/env ruby

require 'rubygems'
#require 'uri'
require 'net/http'
require 'json'
require 'base64'


module Transmission

  class Client

    # initialize a new client instance
    def initialize(server, username=nil, password=nil)
      @server = server
      @username = username
      @password = password

      # do the first query to get the session id
      @tag = 0
      @session_id = nil
      is_running?
    end

    # returns true if the transmission server is available, false if not
    def is_running?
      request('session-get')
      true
    rescue
      false
    end

    # start the transmission server if it is currently not running
    def start_server_if_not_running(cmd, pause=5)
      return if is_running?
      system(cmd)
      sleep(pause)
      list
    rescue Exception => ex
      throw StandardError.new("unable to start new transmission server: #{ex}!")
    end

    # return a list of torrents currently down- or uploading
    def list()
      resp = request('torrent-get',
                     :fields => ['id', 'name', 'isFinished', 'status', 'leftUntilDone'])
      resp['torrents'] if resp
    end

    # add a new torrent to be downloaded
    def add(torrent, download_dir)
      request('session-set', :'download-dir' => download_dir)
      resp = request('torrent-add', :metainfo => Base64.strict_encode64(torrent))
      return resp['torrent-added']['id']
    end

    # delete a torrent from the list of current torrents
    def remove(torrent_id, delete_data=false)
      request('torrent-remove', :ids => [torrent_id], :'delete-local-data' => delete_data)
    end

    # delete all torrents which where completely downloaded
    def remove_finished_torrents
      list.each do |torrent|
        remove(torrent['id']) if torrent['leftUntilDone'] == 0
      end
    end

    # kill the transmission server
    def shutdown
      request('session-close')
    end


  private

    def request(cmd, *args)
      # build the command structure
      data = {:method => cmd, :tag => @tag}
      data[:arguments] = args[0] if args[0]
      body = JSON[data]
      @tag += 1

      # initialize the query
      url = URI.parse(@server)
      req = Net::HTTP::Post.new(url.path)
      req['Content-Type'] = 'application/json'
      req['X-Transmission-Session-Id'] = @session_id if @session_id
      req.body = body

      # execute the query and parse the result
      resp = Net::HTTP.new(url.host, url.port).start { |http| http.request(req) }
      if resp.code == '409' then
        @session_id = resp['X-Transmission-Session-Id']
        nil
      elsif resp.code != '200' then
        raise StandardError.new("invalid http result code #{resp.code} received!")
      else
        data = JSON.parse(resp.body)
        raise StandardError.new("invalid command: #{data['result']}!") unless data['result'] == 'success'
        return data['arguments']
      end
    end

  end
end

