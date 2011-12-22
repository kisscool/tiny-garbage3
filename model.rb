# vim: set softtabstop=2 shiftwidth=2 expandtab :
# (c) 2011 KissCool
require 'rubygems'
require 'socket'
# use Bundler if present
begin
  ENV['BUNDLE_GEMFILE'] = File.join(File.dirname(__FILE__), './Gemfile')
  require 'bundler/setup'
rescue LoadError
end
# let's load the Redis stuff
require 'redis'
require 'digest/md5'
require 'shellwords'

# useful for UTF-8 support
$KCODE = "U"

# Originally some of this code has been derived from Zouchaoqun's ezFtpSearch project
# It is not the case anymore, but kuddos to his work anyway

###############################################################################
################### LOAD OF CONFIGURATION

# defaults values
PORT             = 21
IGNORED_DIRS     = ". .. .svn"
LOGIN            = "anonymous"
PASSWORD         = "garbage3"
DEFAULT_FTP_NAME = "anonymous ftp"
WORDS_SEPARATORS = [ /\s/ , /,/ , /\(|\)/ , /;/ , /\./ , /_/ , /\'/ , /[[:punct:]]/ , /:/ , /!/ , /\?/ , /-/ , /\[|\]/ , /\|/ , /\\/ , /`/ , /\{|\}/ , /~/ , /"/ ]     # those are the separators for the inverted index

# here we load config options
# those options can overwrite the default values above
require File.join(File.dirname(__FILE__), './config.rb')

###############################################################################
################### INTERNAL DOCUMENTATION

# == Database Design
#
# === Introduction
#
# We have five top level namespaces :
# - global : handle global variables
# - entry  : handle scanned entries, each entry is a file or a directory on a given host
# - ftp    : handle informations for each host we are scanning
# - word   : handle the reversed index we will use for searching
# - tmp    : handle the cache for research
#
# === Global
#
# Contains the following keys :
# - hosts : a set of all the registered FTP server, identified by their IP address
#
# ex : global:hosts => { "192.168.0.5", "192.168.0.4" }
#
# === Entry
#
# Contains individual keys for each entry (a file or a directory), in the form IP:PATH.
# Each entry contains a hash with the following items :
# - directory      : check if the entry is a directory or not
# - entry_datetime : date of the entry, as reported by the FTP server
# - size           : size of the entry, as reported by the FTP server
# - name           : basename of the entry, this redundancy is used to speed-up sort operations
#
# ex : 
# entry:192.168.0.5:/animes/plip/plop => {
#   directory      => "true",
#   name           => "plop",
#   entry_datetime => "1324400850",
#   size           => "43"
# }
#
# === FTP
#
# Contains a sub-level of keys for each FTP server, identified by their IP address.
# Each sub-level has the following subkeys :
# - $IP:good_timestamp     : timestamp of the last known good version of the FTP index
# - $IP:list_timestamp     : set of timestamped index registered in the database
# - $IP:entries:$timestamp : set of the FTP index at the given timestamp
# - $IP:name               : name of the given FTP server
# - $IP:is_alive           : was the given FTP server alive during the last check?
# - $IP:last_ping          : time of the last check
# - $IP:total_size	   : Cached value of the total size of the FTP server
# - $IP:total_files        : Cached value of the total number of files in the FTP server
#
# ex :
# ftp:192.168.0.5:good_timestamp  => "1324400857"
# ftp:192.168.0.5:list_timestamp  => { "1324400857" }
# ftp:192.168.0.5:1324400857      => { "/animes/plip/plop", "/animes/plip/plap", ... }
# ftp:192.168.0.5:name            => "plop ftp"
# ftp:192.168.0.5:is_alive        => "true"
# ftp:192.168.0.5:last_ping       => "1324400855"
# ftp:192.168.0.5:total_size      => "2477566119194"
# ftp:192.168.0.5:total_files     => "155086"
#
# === Word
#
# Contains individual keys for each word or group of words in the reverse dictionnary.
# Each key is linked to a set of entries containing this word or group of word.
#
# ex :
# word:"plop" => { "entry:192.168.0.5:/animes/plip/plop", ... }
#
# === Tmp
#
# Contains temporary entries in order to speed-up search operations.
# Their uniqueness is determined by the use of a MD5 digest.
#
# ex :
# tmp:7242d6c91121f8e2e87803855c028e55 => { "entry:192.168.0.5:/animes/plip/plop", ... }
#
#
#
#
# == The Scan Process
#
# The scan process of an individual FTP server follows those phases :
# 1. Registration of a new index timestamp
# 2. Scan of the FTP server
# 3. Promotion of the new timestamp
# 4. Cleaning of old file entries and old index
# 5. Updating of the reverse index (word index)
# 6. Refresh of cached values
#
#
#
#

###############################################################################
################### ORM MODEL CODE (do not edit if you don't understand)





module Entry

  #
  # gives the remote path of the entry, eg. ftp://host/full_path
  #
  def self.remote_path(ip, path)
    "ftp://" + ip + path
  end

  #
  # gives an array of array with informations for each file of a given host :
  # each sub-array contains the following items :
  # path, size, entry_datetime
  # ex : [["/animes/plip/plop", "50034", "1324476909"], ["/animes/plip/plap", "50034", "1324476909"]]
  #
  def self.list(ip)
    # we check for existence
    $db.exists("ftp:#{ip}:good_timestamp") or return -1

    # then we get all the entries of the good timestamp index and compare it to the list of entry:IP:* keys
    good_timestamp = $db.get("ftp:#{ip}:good_timestamp")
    list = $db.smembers("ftp:#{ip}:entries:#{good_timestamp}")
    entry_list = []
    list.each do |entry|
      entry_line = [entry]
      entry_line << $db.hget("entry:#{ip}:#{entry}", "size")
      entry_line << $db.hget("entry:#{ip}:#{entry}", "entry_datetime")
      entry_list << entry_line
    end
    return entry_list
  end

  #
  # This method will quickly purge all the dead entries from the entry:* hierarchy of a given IP
  # based on an old good timestamp taken as reference
  # It will return the number of deleted items
  #
  def self.purge_quick(ip, old_good_timestamp)
    # we check for existence
    $db.exists("ftp:#{ip}:good_timestamp") or return -1
    $db.sismember("ftp:#{ip}:list_timestamp", old_good_timestamp) or return -2

    # then we get the new good timestamp and the diff between the two versions
    new_good_timestamp = $db.get("ftp:#{ip}:good_timestamp")
    diff = $db.sdiff("ftp:#{ip}:entries:#{old_good_timestamp}", "ftp:#{ip}:entries:#{new_good_timestamp}")

    # let's delete the old stuff
    $db.multi do
      # we destroy old entries in the entry:* hierarchy
      diff.each do |x|
        $db.del("entry:#{ip}:#{x}")
      end
    end
    # and terminate last traces of any other index in the ftp:IP:entries:* hierarchy
    FtpServer.purge(ip)

    # then we return the number of deleted entries in the entry:* hierarchy
    return diff.length
  end

  #
  # This method will slowly but surely delete all the dead entries which are not
  # in existence according to the current good timestamp for a given ip
  # It will return the number of deleted items
  #
  def self.purge_slow(ip)
    # we check for existence
    $db.exists("ftp:#{ip}:good_timestamp") or return -1

    # then we get all the entries of the good timestamp index and compare it to the list of entry:IP:* keys
    good_timestamp = $db.get("ftp:#{ip}:good_timestamp")
    valid_entries = $db.smembers("ftp:#{ip}:entries:#{good_timestamp}")
    valid_entries.collect! {|x| "entry:#{ip}:#{x}"}
    keys_entries = $db.keys("entry:#{ip}:*")
    diff = keys_entries - valid_entries

    $db.multi do
      # we destroy old entries in the entry:* hierarchy
      diff.each do |x|
        $db.del(x)
      end
    end
    # and terminate last traces of any other index in the ftp:IP:entries:* hierarchy
    FtpServer.purge(ip)
    return diff.length    
  end
end










module FtpServer

  #
  # gives the url of the FTP
  #
  def self.url(ip)
    "ftp://" + ip
  end

  #
  # gives the name of the FTP
  #
  def self.name(ip)
    $db.get("ftp:#{ip}:name")
  end

  #
  # rename the FTP server
  #
  def self.rename(ip,new_name)
    $db.sismember("global:hosts", ip) or return -1
    $db.set("ftp:#{ip}:name", new_name)
  end
  
  #
  # gives the number of registered FTP
  #
  def self.ftp_number
    $db.scard('global:hosts')
  end

  #
  # gives an array of informations about one server, which contains :
  # ip, name, number of files, size, good timestamp (last scan), is_alive
  # ex : ["192.168.0.1", "anonymous ftp", "178531", "5020887691106", "1324476909", "true"]
  #
  def self.ftp_info(ip)
    ftp_line = [ip]
    ftp_line << $db.get("ftp:#{ip}:name")
    ftp_line << $db.get("ftp:#{ip}:total_files")
    ftp_line << $db.get("ftp:#{ip}:total_size")
    ftp_line << $db.get("ftp:#{ip}:good_timestamp")
    ftp_line << $db.get("ftp:#{ip}:is_alive")
    return ftp_line
  end

  #
  # gives an array of array with informations about every servers
  # each sub-array will contain : 
  # ip, name, number of files, size, good timestamp (last scan), is_alive
  # ex : [["192.168.0.1", "anonymous ftp", "178531", "5020887691106", "1324476909", "true"], ["10.2.0.1", "anonymous ftp", "10353", "674893009291", "1324400214", "true"]]
  #
  def self.ftp_list
    list = $db.smembers('global:hosts')
    ftp_list = []
    list.each do |ip|
      ftp_list << ftp_info(ip)
    end
    return ftp_list
  end

  #
  # calculate the total size of the given FTP server
  #
  def self.calculate_ftp_size(ip)
    # we retrieve entries
    good_timestamp = $db.get "ftp:#{ip}:good_timestamp"
    return -1 if good_timestamp.nil?
    entries = $db.smembers "ftp:#{ip}:entries:#{good_timestamp}"
    ftp_size = 0
    #then we add values
    entries.each do |entry|
      entry_hash = $db.hgetall "entry:#{ip}:#{entry}"
      ftp_size = ftp_size + entry_hash['size'].to_i if entry_hash['directory'] == 'false'
    end
    return ftp_size
  end

  #
  # calculate the total number of files of the given FTP server
  #
  def self.calculate_ftp_files(ip)
    # we retrieve entries
    good_timestamp = $db.get "ftp:#{ip}:good_timestamp"
    return -1 if good_timestamp.nil?
    entries = $db.smembers "ftp:#{ip}:entries:#{good_timestamp}"
    ftp_files = 0
    #then we add values
    entries.each do |entry|
      entry_hash = $db.hgetall "entry:#{ip}:#{entry}"
      ftp_files += 1 if entry_hash['directory'] == 'false'
    end
    return ftp_files
  end

  #
  # refresh cache for total_size and total_files
  # this method must be used as a batch after a global scan
  #
  def self.refresh_cache(ip)
    $db.set("ftp:#{ip}:total_size", FtpServer.calculate_ftp_size(ip))
    $db.set("ftp:#{ip}:total_files", FtpServer.calculate_ftp_files(ip))
  end

  #
  # gives the size in the FTP, according to the cache
  #
  def self.ftp_size(ip)
    $db.get("ftp:#{ip}:total_size").to_i || 0
  end

  #
  # gives the number of files in the FTP, according to the cache
  #
  def self.number_of_files(ip)
    $db.get("ftp:#{ip}:total_files").to_i || 0
  end

  #
  # gives the added total sizes of every FTP servers
  #
  def self.added_total_size
    hosts = $db.smembers "global:hosts"
    return -1 if hosts.nil?
    sum = 0
    hosts.each do |ip|
      sum += $db.get("ftp:#{ip}:total_size").to_i || 0
    end
    return sum
  end

  #
  # gives the added total number of files of every FTP servers
  #
  def self.added_total_number_of_files
    hosts = $db.smembers "global:hosts"
    return -1 if hosts.nil?
    sum = 0
    hosts.each do |ip|
      sum += $db.get("ftp:#{ip}:total_files").to_i || 0
    end
    return sum
  end

  #
  # give the latest selected value from every FTP
  # example of values : last_ping or good_timestamp
  #
  def self.global_last(value)
    # in case it is a symbol, we change it to a string
    value = value.to_s
    # then we order it
    $db.sort("global:hosts", :by => "ftp:*:#{value}", :get => "ftp:*:#{value}", :order => "desc")[0]
  end

  #
  # remove the given FTP host and all informations about it
  #
  def self.remove(ip)
    # first we remove the entry:$ip:* keys
    keys_entries = $db.keys("entry:#{ip}:*")
    $db.multi do
      keys_entries.each do |x|
        $db.del(x)
      end
    end
    # then we do the same with the ftp:$ip:* keys
    keys_entries = $db.keys("ftp:#{ip}:*")
    $db.multi do
      keys_entries.each do |x|
        $db.del(x)
      end
    end
    # and we finish by removing the host from the global
    # list
    $db.srem("global:hosts", ip)

    # last but not least we must update the Word index cache
    Word.purge
  end

  #
  # purge old entries in the ftp:IP:* hierarchy
  #
  def self.purge(ip)
    good_timestamp = $db.get("ftp:#{ip}:good_timestamp")
    outdated_timestamps = $db.smembers("ftp:#{ip}:list_timestamp") - [good_timestamp]
    $db.multi do
      outdated_timestamps.each do |x|
        $db.del("ftp:#{ip}:entries:#{x}")
        $db.srem("ftp:#{ip}:list_timestamp", x)
      end
    end
  end

  #
  # gives the list of FTP servers hosts depending if they are online or offline
  #
  def self.list_by_status(state)
    hosts = $db.smembers "global:hosts"
    return -1 if hosts.nil?
    results = []
    hosts.each do |ip| 
      if $db.get("ftp:#{ip}:is_alive") == state.to_s
        results << ip
      end
    end
    return results
  end

  #
  # handle the ping scan backend
  #
  def self.ping_scan_result(ip, is_alive)
    # fist we check if the host is known in the database
    if $db.sismember("global:hosts", ip)
      # if the server does exist in the database
      # then we update its status
      $db.multi do
        $db.set("ftp:#{ip}:is_alive", is_alive)
        $db.set("ftp:#{ip}:last_ping", Time.now)
      end
    else
     # if the server doesn't exist yet
      if is_alive
        # but that he is a FTP server
        # then we create it
        # after a quick reverse DNS resolution
        begin
          name = Socket.getaddrinfo(line, 0, Socket::AF_UNSPEC, Socket::SOCK_STREAM, nil, Socket::AI_CANONNAME)[0][2]
        rescue
          name = "anonymous ftp"
        end
        $db.multi do
          $db.set("ftp:#{ip}:name", name)
          $db.set("ftp:#{ip}:is_alive", true)
          $db.set("ftp:#{ip}:last_ping", Time.now.to_i.to_s)
          
          $db.sadd("global:hosts", ip)
        end
      end
    end
  end


  ###################################
  # BEWARE : The holy scan is below !
  ###################################
  
  #
  # this is the method which launch the process to index an FTP server
  #
  def self.get_entry_list(ip ,max_retries = 3)
    require 'net/ftp'
    require 'net/ftp/list'
    require 'iconv'
    require 'logger'
    @max_retries = max_retries.to_i
    # with a value of 1 we will simply ignore charset errors without retry
    @max_retries_get_list = 2
    BasicSocket.do_not_reverse_lookup = true

    # Trying to open ftp server, exit on max_retries
    retries_count = 0
    begin
      @logger = Logger.new(File.dirname(__FILE__) + '/log/spider.log', 0)
      @logger.formatter = Logger::Formatter.new
      @logger.datetime_format = "%Y-%m-%d %H:%M:%S"
      @logger.info("on #{ip} : Trying ftp server #{$db.get "ftp:#{ip}:name"}")
      ftp = Net::FTP.open(ip, LOGIN, PASSWORD)
      ftp.passive = true
    rescue => detail
      retries_count += 1
      @logger.error("on #{ip} : Open ftp exception: " + detail.class.to_s + " detail: " + detail.to_s)
      @logger.error("on #{ip} : Retrying #{retries_count}/#{@max_retries}.")
      if (retries_count >= @max_retries)
        @logger.error("on #{ip} : Retry reach max times, now exit.")
        exit
      end
      ftp.close if (ftp && !ftp.closed?)
      @logger.error("on #{ip} : Wait 30s before retry open ftp")
      sleep(30)
      retry
    end

    # Trying to get ftp entry-list
    get_list_retries = 0
    begin
      @logger.info("on #{ip} : Server connected")
      start_time = Time.now
      @entry_count = 0
      
      # registering the new timestamp
      @new_good_timestamp = start_time.to_i.to_s
      $db.sadd("ftp:#{ip}:list_timestamp", @new_good_timestamp)
      
      # building the index
      get_list_of(ip, ftp)

      process_time = Time.now - start_time
      name = $db.get("ftp:#{ip}:name")
      name ||= DEFAULT_FTP_NAME
      @logger.info("on #{ip} : Finish getting list of server " + name + " in " + process_time.to_s + " seconds.")
      @logger.info("on #{ip} : Total entries: #{@entry_count}. #{(@entry_count/process_time).to_i} entries per second.")
    rescue => detail
      get_list_retries += 1
      @logger.error("on #{ip} : Get entry list exception: " + detail.class.to_s + " detail: " + detail.to_s)
      @logger.error("on #{ip} : Retrying #{get_list_retries}/#{@max_retries}.")
      raise if (get_list_retries >= @max_retries)
      retry
    ensure
      ftp.close if !ftp.closed?
      @logger.info("on #{ip} : Ftp connection closed.")
    end

    # now we promote the new good timestamp and clean old entries
    start_time = Time.now
    @logger.info("on #{ip} : Cleaning old entries, new good_timestamp will be : " + @new_good_timestamp)
    begin
      old_good_timestamp = $db.getset("ftp:#{ip}:good_timestamp", @new_good_timestamp)
      #count = Entry.purge_quick(ip, old_good_timestamp) if ! old_good_timestamp.nil?
      count = Entry.purge_slow(ip)  # very slow, but more reliable in case of human error from myself
    rescue => detail
      @logger.error("on #{ip} : Error during cleaning procedure " + detail.class.to_s + " detail: " + detail.to_s)
      exit
    end
    process_time = Time.now - start_time
    @logger.info("on #{ip} : Cleaning procedure destroyed #{count} items and took " + process_time.to_s + " seconds.")

    # now we update our reverse index for searches
    start_time = Time.now
    @logger.info("on #{ip} : Wordindex update procedure")
    begin
      Word.update(ip)
    rescue => detail
      @logger.error("on #{ip} : Error during wordindex procedure " + detail.class.to_s + " detail: " + detail.to_s)
      exit
    end
    process_time = Time.now - start_time
    @logger.info("on #{ip} : Wordindex update procedure took " + process_time.to_s + " seconds.")

    # then finaly we refresh the cache
    start_time = Time.now
    @logger.info("on #{ip} : Refresh of cache update procedure")
    begin
      FtpServer.refresh_cache(ip)
    rescue => detail
      @logger.error("on #{ip} : Error during refresh of cache procedure " + detail.class.to_s + " detail: " + detail.to_s)
      exit
    end
    process_time = Time.now - start_time
    @logger.info("on #{ip} : Refresh of cache update procedure took " + process_time.to_s + " seconds.")


    # not the smartiest solution, but closing the log device can be a real issue in a multi-threaded environment
    @logger.info("on #{ip} : scan finished.")
    #@logger.close
  end


private
  

  #
  # get entries under parent_path, or get root entries if parent_path is nil
  #  
  def self.get_list_of(ip, ftp, parent_path = nil, parents = [])
    ic = Iconv.new('UTF-8', 'ISO-8859-1')
    ic_reverse = Iconv.new('ISO-8859-1', 'UTF-8')

    retries_count = 0
    begin
      entry_list = parent_path ? ftp.list(parent_path) : ftp.list
    rescue => detail
      retries_count += 1
      @logger.error("on #{ip} : Ftp LIST exception: " + detail.class.to_s + " detail: " + detail.to_s)
      @logger.error("on #{ip} : Ftp LIST exception: the parent_path (if present) was : " + parent_path) if ! parent_path.nil?
      @logger.error("on #{ip} : Retrying get ftp list #{retries_count}/#{@max_retries_get_list}")
      return 0 if (retries_count >= @max_retries_get_list)
      
      reconnect_retries_count = 0
      begin
        ftp.close if (ftp && !ftp.closed?)
        @logger.error("on #{ip} : Wait 30s before reconnect")
        sleep(30)
        ftp.connect(ip)
        ftp.login(LOGIN, PASSWORD)
        ftp.passive = true
      rescue => detail
        reconnect_retries_count += 1
        @logger.error("on #{ip} : Reconnect ftp failed, exception: " + detail.class.to_s + " detail: " + detail.to_s)
        @logger.error("on #{ip} : Retrying reconnect #{reconnect_retries_count}/#{@max_retries}")
        raise if (reconnect_retries_count >= @max_retries)
        retry
      end
      
      @logger.error("on #{ip} : Ftp reconnected!")
      retry
    end

    entry_list.each do |e|
      # Some ftp will send 'total nn' string in LIST command
      # We should ignore this line
      next if e.nil?
      next if /^total/.match(e)

      # usefull for debugging purpose
      #puts "#{@entry_count} #{e}"

      begin
        #e_utf8 = ic.iconv(e)
        e_utf8 = e
      rescue => detail
        @logger.error("on #{ip} : Iconv failed, exception: " + detail.class.to_s + " detail: " + detail.to_s + " file ignored. raw data: " + e)   
        next       
      end

      begin
        entry = Net::FTP::List.parse(e_utf8)
      rescue => detail
        @logger.error("on #{ip} : Net::FTP::List.parse exception:" + detail.class.to_s + " detail: " + detail.to_s + " file ignored. raw data: " + e_utf8)
        next
     end

      next if IGNORED_DIRS.include?(entry.basename)
      @entry_count += 1

      begin
        file_datetime = entry.mtime.strftime("%Y-%m-%d %H:%M:%S")
      rescue => detail
        @logger.error("on #{ip} : strftime failed, exception: " + detail.class.to_s + " detail: " + detail.to_s + " raw entry : " + e )
      end
      
      #full_path = (parent_path ? parent_path : '') + '/' + ic.iconv(entry.basename)
      full_path = (parent_path ? parent_path : '') + '/' + entry.basename

      # here we build the document
      # that will be inserted in
      # the datastore
      $db.multi do
        $db.hmset("entry:#{ip}:#{full_path}", "directory", entry.dir?, "name", entry.basename, "size", entry.filesize, "entry_datetime", entry.mtime.to_i.to_s)
        $db.sadd("ftp:#{ip}:entries:#{@new_good_timestamp}", full_path)
      end
      
      if entry.dir?
        #ftp_path = (parent_path ? parent_path : '') + '/' + ic.iconv(entry.basename)
        ftp_path = (parent_path ? parent_path : '') + '/' + entry.basename
        get_list_of(ip, ftp, ftp_path, parents)
      end
    end
  end


end









module Word

  #
  # This method will return an array of the words we
  # want to match for the given entry in the search engine
  #
  def self.split_in_words(entry)
    basename = File.basename(entry)
    basename.downcase!
    results = []
    WORDS_SEPARATORS.each do |regexp|
      results << basename.split(regexp)
    end
    results = results.flatten.uniq - [""]
    return results
  end

  #
  # This method will insert the given entry in the word index
  #
  def self.insert_entry(ip,entry)
    words = Word.split_in_words(entry)
    sum = 0
    $db.multi do
      words.each do |word|
        $db.sadd("word:#{word}", "entry:#{ip}:#{entry}")
      end
    end
  end

  #
  # This method will update all the word index for the given IP
  #
  def self.update(ip)
    # we retrieve entries
    good_timestamp = $db.get "ftp:#{ip}:good_timestamp"
    return -1 if good_timestamp.nil?
    entries = $db.smembers "ftp:#{ip}:entries:#{good_timestamp}"
   
    # then treat each entry
    entries.each do |entry|
      Word.insert_entry(ip,entry)
    end
  end

  #
  # This method will purge the word index from invalid entries
  # this method is especially slow as we have to check that
  # every member of every word:* set still exists in the entry:*
  # hierarchy
  # It is to be used at the end of a global scan
  #
  def self.purge
    # purge of the word:* entries
    keys_entries = $db.keys("word:*")
    keys_entries.each do |key|
      key_members = $db.smembers(key)
      key_members.each do |entry|
        if ! $db.exists(entry)
          $db.srem(key, entry)
        end
      end
    end
    # purge of the tmp:* entries
    keys_entries = $db.keys("tmp:*")
    $db.multi do
      keys_entries.each do |key|
        $db.del(key)
      end
    end
  end

  #
  # search in the inverted index
  # return an array of results
  # especially useful from console.rb
  #
  def self.search(search_terms)
    search_terms.collect! {|x| 'word:' + x.downcase}
    results = $db.sinter(*search_terms)
  end

  #
  # return an array of entries
  # the params are :
  # query : searched terms
  # page : offset of the page of results we must return
  # order : order string, in the form of "ftp", "size", "name", "date" or "size.desc"
  # online : restrict the query to online FTP servers or to every known ones
  # ex :
  # [1, [["192.168.0.1", "/animes/Plip", "1146175200", "4"], ["192.168.0.1", "/animes/Flock/Plip 01.ogm", "1145570400", "734022487"]]]
  #
  def self.complex_search(query="", page=1, sort="ftp.asc", online=true)
    # here we define how many results we want per page
    per_page = 20

    # basic checks and default options
    query ||= ""
    page  ||= 1
    if page < 1
     page = 1
    end
    sort  ||= "ftp.asc"
    online ||= true

    # we build the query and generate the temporary set if 
    # it doesn't already exists in temp:*
    md5 = Digest::MD5.hexdigest(query)
    tmpkey = 'tmp:' + md5
   
    if ! $db.exists(tmpkey)
      # we take the time to actually execute the query
      # only if it is not already in cache
      search_terms = Shellwords.shellwords(query)
      search_terms.collect! {|x| 'word:' + x.downcase}
      $db.multi do
        $db.sinterstore(tmpkey, *search_terms)
        $db.expire(tmpkey, 3600)
      end
    end

    # how many pages we will have
    page_count = ($db.scard(tmpkey).to_f / per_page).ceil

    # we define options for the sort
    limit = [(page - 1) * per_page, per_page]
    by = (sort.include?('ftp')) ? '' : "*->#{sort.split('.')[0]}"
    order=''
    order << ( (sort.include?('desc')) ? 'desc' : '' )
    order << ( (sort.include?('size')) ? '' : ' alpha' )

    options = {
     :limit => limit,
     :by => by,
     :order => order,
     :get => ["#", "*->entry_datetime", "*->size"]
    }

    # then we do the sort itself
    results_raw = $db.sort(tmpkey, options)
    # and make it match a more usable format :
    # array of arrays, with each sub-array in the following format :
    # ip, path, entry_datetime, size
    results = results_raw.each_slice(3).to_a.collect do |x| 
      exploded_entry = x[0].split(/:/,3)
      [exploded_entry[1], exploded_entry[2], x[1], x[2]]
    end

    # we will trim the results if online is true
    if online
      ftp_list = FtpServer.list_by_status(true)
      results.delete_if {|x| ! ftp_list.include?(x[0]) }
    end

    # finally we return both informations
    return [ page_count, results ]
  end
end
