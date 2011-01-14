#!/usr/bin/env ruby

require 'rubygems'
require 'socket'
require 'bencode'
require 'etc'


module Btpd

  # error class for btpd client errors
  class Error < StandardError
    attr_reader :status

    def initialize(status, msg='')
      @status = status
      super(msg)
    end
  end

  # error result codes for calls to the server
  ECOMMERR = 1         # communication error
  EBADCDIR = 2         # bad content directory
  EBADT = 3            # bad torrent
  EBADTENT = 4         # bad torrent entry
  EBADTRACKER = 5      # bad tracker
  ECREATECDIR = 6      # could not create content directory
  ENOKEY = 7           # no such key
  ENOTENT = 8          # no such torrent entry
  ESHUTDOWN = 9        # server is shutting down
  ETACTIVE = 10        # torrent is active
  ETENTEXIST = 11      # torrent entry exists
  ETINACTIVE = 12      # torrent is inactive
  EGENERIC = 99        # generic error for all other cases

  # the states a torrent can be in at any given time
  TSTATE_INACTIVE = 0
  TSTATE_START = 1
  TSTATE_STOP = 2
  TSTATE_LEECH = 3
  TSTATE_SEED = 4

  # available information fields for the tget() call
  TVAL_CGOT = 0        # bytes downloaded so far (NUM)
  TVAL_CSIZE = 1       # size of the complete file (NUM)
  TVAL_DIR = 2         # download directory (STR)
  TVAL_NAME = 3        # name of the torrent file (STR)
  TVAL_NUM = 4         # internal index number of the torrent (NUM, number)
  TVAL_IHASH = 5       # torrent info hash (STR)
  TVAL_PCGOT = 6       # pieces got (NUM)
  TVAL_PCOUNT = 7      # number of peers (NUM)
  TVAL_PCCOUNT = 8     # piece count (NUM)
  TVAL_PCSEEN = 9      # pieces seen (NUM)
  TVAL_RATEDWN = 10    # current download rate (NUM)
  TVAL_RATEUP = 11     # current upload rate (NUM)
  TVAL_SESSDWN = 12    # number of bytes downloaded in the current session
  TVAL_SESSUP = 13     # number of bytes uploaded in the current session
  TVAL_STATE = 14      # status of the torrent (NUM, defined in TSTATE_xxx)
  TVAL_TOTDWN = 15     # number of bytes totally downloaded so far (NUM)
  TVAL_TOTUP = 16      # number of bytes totally uploaded so far (NUM)
  TVAL_TRERR = 17      # torrent errors  (NUM)
  TVAL_TRGOOD = 18     # torrent good (NUM)
  TVAL_COUNT = 19


  # client class to communicate with the server
  class Client
    attr_reader :socket_path
    @socket_path = ''
    attr_accessor :debug
    @debug = false

    # constructor. If no communication socket path is given we're trying
    # to use the default BTPD one in the user's home folder
    def initialize(socket_path=nil)
      @socket_path = if socket_path.nil?
                       "#{Etc.getpwuid.dir}/.btpd/sock" 
                     else
                       socket_path
                     end
    end

    # returns true if a btpd server is currently running
    def is_running?
      tget([TVAL_STATE])
      return true
    rescue
      return false
    end

    # start a new btpd server if no currently running instance is available
    def start_server_if_not_running(executable = nil)
      unless executable
        dir = File.dirname(__FILE__)
        executable = "#{dir}/bin/btpd"
      end
      unless is_running?
        raise Error(EGENERIC, "#{executable} isn't available!") unless File.executable?(executable)
        system(executable)
      end
    end

    # initialize a server shutdown
    def die!
      execute_command(['die'])['code']
    end

    # set the upload/ download transfer rate limits in kbyte
    def rate(upload, download)
      execute_command(['rate', upload * 1024, download * 1024])['code']
    end

    # stop all currently running torrent transfers
    def stop_all
      execute_command(['stop-all'])['code']
    end

    # start a specific torrent. The parameter is either the 20-char
    # torrent hash value or numeric position from the tget output
    def start(hash_or_id)
      execute_command(['start', hash_or_id])['code']
    end

    # restart all previously stopped torrents
    def start_all
      execute_command(['start-all'])['code']
    end

    # delete a given torrent
    def del(hash_or_id)
      execute_command(['del', hash_or_id])['code']
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
      resp['num']
    end

    # read information about the torrent from the server. The argument is a list
    # of TVAL_xxx field IDs to fetch. The resulting array will contain a list of
    # values the same order as the field list argument.
    def tget(fields)
      resp = execute_command(['tget', {
                                'from' => 0,  # query all torrents
                                'keys' => fields}])

      # filter the type information from the results and return
      # the the values of the fields without its types
      resp['result'].map do |torrent|
        (0...torrent.length).step(2).map { |idx| torrent[idx + 1] }
      end
    end

    # list the current downloading torrents and their status
    def dump_state
      states = ['inactive', 'starting', 'stopped', 'leeching', 'seeding']
      torrents = tget([TVAL_CGOT, TVAL_CSIZE, TVAL_NUM, TVAL_NAME, TVAL_STATE])
      torrents.each do |torrent|
        puts "%02d: %s %s (%d%%)" % [torrent[2],
                                     torrent[3],
                                     states[torrent[4]],
                                     (torrent[0]/(torrent[1]/100.0)).round]
      end
    end

    # send a command to the btpd client and return its response
    def execute_command(cmd)
      # send the bencoded command string
      encoded = cmd.bencode()
      sock = UNIXSocket.open(@socket_path)
      sock.send([encoded.length].pack('L'), 0)
      sock.send(encoded, 0)
      puts "---> #{encoded}" if @debug

      # first get the length of the response, then read the response itself
      len = sock.recvfrom(4)[0].unpack('L')[0]
      raise "communication error with btpd!" if not len or len == 0
      buffer = sock.recvfrom(len)[0]
      puts "<--- #{buffer}" if @debug
      sock.close

      # finally return the decoded bencode data
      resp = BEncode.load(buffer)
      raise Error(resp['code']) if resp['code'] != 0
      resp
    end
    private :execute_command

  end
end

