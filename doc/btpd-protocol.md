btpd client protocol description
================================

* communication with the server is handled via a UNIX socket, normally ~/.btpd/sock
* commands and responses get transferred as length-annotated Bencode strings
* each Bencode string is prefixed by its length in bytes as a 4-byte uint32
* with the exeception of the 'tget' command the response to a command is a dictionary
  with at least the key "code" containing a status code as described in the table below

  
available commands
------------------

* die(): initialize a shutdown
* rate(up, down): set the upload-/download rate, the parameters are integers
* add(dict): add a new torrent, the dict contains the keys "torrent", "content" and "name"
* tget(whatTorrents, listOfTVALfields): read the given attributes for a specific set of torrents from the server

* stop-all(): stop all running torrents
* start-all(): (re)start all stopped torrents
* stop(numOrHash): stop a running torrent
* start(numOrHash): (re)start a stopped torrent
* del(numOrHash): delete a specific torrent


response status codes
---------------------

*  0: OK
*  1: communication error
*  2: bad content directory
*  3: bad torrent
*  4: bad torrent entry
*  5: bad tracker
*  6: could not create content directory
*  7: no such key
*  8: no such torrent entry
*  9: server is shutting down
* 10: torrent is active
* 11: torrent entry exists
* 12: torrent is inactive


torrent states
--------------
* 0: inactive
* 1: starting
* 2: stopped
* 3: leeching
* 4: seeding


possible fields for the tget() command
--------------------------------------
*  0: IPC_TVAL_CGOT
*  1: IPC_TVAL_CSIZE
*  2: IPC_TVAL_DIR
*  3: IPC_TVAL_NAME
*  4: IPC_TVAL_NUM
*  5: IPC_TVAL_IHASH
*  6: IPC_TVAL_PCGOT
*  7: IPC_TVAL_PCOUNT
*  8: IPC_TVAL_PCCOUNT
*  9: IPC_TVAL_PCSEEN
* 10: IPC_TVAL_RATEDWN
* 11: IPC_TVAL_RATEUP
* 12: IPC_TVAL_SESSDWN
* 13: IPC_TVAL_SESSUP
* 14: IPC_TVAL_STATE
* 15: IPC_TVAL_TOTDWN
* 16: IPC_TVAL_TOTUP
* 17: IPC_TVAL_TRERR
* 18: IPC_TVAL_TRGOOD
* 19: IPC_TVALCOUNT


communication examples
----------------------

* command:  \x07\x00\x00\x00l3:diee 
  response: \x0b\x00\x00\x00d4:codei0ee

* command:  \x0c\x00\x00\x00l8:stop-alle
  response: \x0b\x00\x00\x00d4:codei0ee


Bencode
-------

* http://en.wikipedia.org/wiki/Bencode
* an integer is encoded as i<number in base 10 notation>e. Leading zeros are not allowed, although the
  number zero is still represented as "0"). Negative values are encoded by prefixing the number with a
  minus sign. The number 42 would thus be encoded as "i42e", 0 as "i0e", and -42 as "i-42e". Negative
  zero is not permitted.
* a byte string (a sequence of bytes, not necessarily characters) is encoded as <length>:<contents>. This
  is similar to netstrings, but without the final comma.) The length is encoded in base 10, like integers,
  but must be non-negative (zero is allowed); the contents are just the bytes that make up the string. The
  string "spam" would be encoded as "4:spam". The specification does not deal with encoding of characters
  outside the ASCII set; to mitigate this, some BitTorrent applications explicitly communicate the encoding
  (most commonly UTF-8) in various non-standard ways.
* a list of values is encoded as l<contents>e . The contents consist of the bencoded elements of the list,
  in order, concatenated. A list consisting of the string "spam" and the number 42 would be encoded as:
  "l4:spami42ee". Note the absence of separators between elements.
* a dictionary is encoded as d<contents>e. The elements of the dictionary are encoded each key immediately
  followed by its value. All keys must be byte strings and must appear in lexicographical order. A dictionary
  that associates the values 42 and "spam" with the keys "foo" and "bar", respectively, would be encoded as
  follows: "d3:bar4:spam3:fooi42ee". (This might be easier to read by inserting some spaces: "d 3:bar 4:spam 3:foo i42e e".)
