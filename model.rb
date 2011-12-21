# vim: set softtabstop=2 shiftwidth=2 expandtab :
# (c) 2009 Zouchaoqun
# (c) 2010 KissCool
require 'rubygems'
require 'socket'
# use Bundler if present
begin
  ENV['BUNDLE_GEMFILE'] = File.join(File.dirname(__FILE__), './Gemfile')
  require 'bundler/setup'
rescue LoadError
end
# let's load the Mongo stuff
require 'mongo'
include Mongo

# some of this code has been derived from Zouchaoqun's ezFtpSearch project
# kuddos to his work

# the code has now become very different than ezFtpSearch


###############################################################################
################### LOAD OF CONFIGURATION

# here we load config options
require File.join(File.dirname(__FILE__), './config.rb')

###############################################################################
################### ORM MODEL CODE (do not edit if you don't know)

#
# the Entry class is a generic class for fields and directories 
module Entry
  # example of a file entry :
  # {
  #   "_id"=>BSON::ObjectId('4cdbf81f2a2cd621f7000001'), 
  #   "directory"=>true, 
  #   "parent_path"=>"/animes/plip", 
  #   "index_version"=>6, 
  #   "entry_datetime"=>"2010-10-16 20:27:00", 
  #   "ftp_server_id"=>BSON::ObjectId('4cdbf72e2a2cd621da000001'), 
  #   "size"=>43, 
  #   "name"=>"plop"
  # }

  # this is the point of entry to every entries
  @@collection = $db['entries']
  def self.collection
    @@collection
  end

  ### methods

  # gives the full path of the entry
  def self.full_path(entry)
    entry['parent_path'].to_s + "/" + entry['name'].to_s
  end

  # gives the remote path of the entry, eg. ftp://host/full_path
  def self.remote_path(entry)
    FtpServer.url(FtpServer.collection.find_one('_id' => entry['ftp_server_id'])) + self.full_path(entry)
  end


  # this method will purge every old entries
  # the offline ftp list is given as an argument so that we are sure
  # it is the list as of the moment of the begining of the scan
  def self.purge(ftp_offline)
    # first we bump the global variable index_version
    FtpServer.incr_index_version
    # then we bump the index_version of offline entries
    Entry.collection.update({ 'ftp_server_id' => {'$in' => ftp_offline} }, {'$set' => {'index_version' => FtpServer.index_version}}, :multi => true)
    # then we remove every entries with an index_version inferior to the global variable
    Entry.collection.remove({'index_version' => {'$lt' => FtpServer.index_version}})
  end

  # return an array of entries
  # the params are :
  # query : searched regexps, in the form of "foo.*bar"
  # page : offset of the page of results we must return
  # order : order string, in the form of "name", ""size" or "size.descending"
  # online : restrict the query to online FTP servers or to every known ones
  def self.complex_search(query="", page=1, order="ftp_server_id.ascending", online=true)
    # here we define how many results we want per page
    per_page = 20

    # basic checks and default options
    query ||= ""
    page  ||= 1
    if page < 1
     page = 1
    end
    order  ||= "ftp_server_id.ascending"
    online ||= true

    # we build the query
    filter = {
      'name' => /#{query}/i,
      'index_version' => FtpServer.index_version
    }
    # we will get the list of FTP _ids to check if online is true
    if online
      ftp_list = FtpServer.list_by_status(true)
      filter.merge!({ 'ftp_server_id' => {'$in' => ftp_list} })
    end

    options = {
      :limit => per_page,
      :skip => (page - 1) * per_page,
      :sort => order.split('.')
    }

    # execute the query
    results = Entry.collection.find(filter, options)
    
    # how many pages we will have
    page_count = (Entry.collection.find(filter).count.to_f / per_page).ceil

    # finally we return both informations
    return [ page_count, results ]
  end

end

#
# each server is documented here
module FtpServer
  # example of a FTP entry :
  # {
  #   "_id"=>BSON::ObjectId('4cdbf72e2a2cd621da000001'), 
  #   "force_utf8"=>true, 
  #   "ftp_encoding"=>"ISO-8859-1", 
  #   "ftp_type"=>"Unix", 
  #   "host"=>"192.168.0.5",
  #   "port"=>21,
  #   "ignored_dirs"=>". .. .svn", 
  #   "is_alive"=>true, 
  #   "last_ping"=>Thu Nov 11 14:01:18 UTC 2010, 
  #   "login"=>"anonymous", 
  #   "password"=>"garbage2"
  #   "name"=>"My FTP", 
  #   "updated_on"=>Thu Nov 11 14:09:19 UTC 2010,
  #   "total_size"=>2477566119194.0,
  #   "total_files"=>155086
  # }


  # point of entry for every FTP servers
  @@collection = $db['ftp_servers']
  def self.collection
    @@collection
  end

  ## methods ##
  

  # gives the url of the FTP
  def self.url(ftp_server)
    "ftp://" + ftp_server['host']
  end

  # gives the total size of all the FTP Servers then insert it in ftp_servers
  # documents for future check
  # this method must be used as a batch after a global scan
  def self.calculate_total_sizes
    # not sure if it is actually the good method to do it
    map    = "function() { emit(this.ftp_server_id, {size: this.size}); }"
    reduce = "function(key, values) { var sum = 0; values.forEach(function(doc) {sum += doc.size}); return {size : sum};}"
    results = Entry.collection.mapreduce(map, reduce, {:query => {'index_version' => FtpServer.index_version, 'directory' => false}})
    self.collection.find.each do |ftp|
      ftp_size = 0
      result = results.find_one('_id' => ftp['_id'])
      ftp_size = result['value']['size'] if ! result.nil?

      self.collection.update(
        { "_id" => ftp["_id"] },
        { "$set" => { :total_size => ftp_size }}
      )
    end
  end

  # gives the added total sizes of every FTP servers
  def self.added_total_size
    sum = 0
    FtpServer.collection.find.each do |a|
      sum += a['total_size'] || 0
    end
    return sum
  end
  
  # gives the total number of files of all the FTP Servers then insert it in ftp_servers
  # document for future check
  # this method must be used as a batch after a global scan
  def self.calculate_total_number_of_files
    self.collection.find.each do |ftp|
      number_of_files = Entry.collection.find('ftp_server_id' => ftp['_id'], 'index_version' => FtpServer.index_version, 'directory' => false).count
      self.collection.update(
        { "_id" => ftp["_id"] },
        { "$set" => { :total_files => number_of_files }}
      )
    end
  end

  # gives the number of files in the FTP
  def self.number_of_files(ftp_server)
    ftp_server['total_files'] || 0
  end

  # give the latest selected value from every FTP
  # example of values : last_ping or updated_on
  def self.global_last(value)
    # in case it is a symbol, we change it to a string
    value = value.to_s
    # then we order it
    self.collection.find.to_a.sort! do |a,b|
      a_time = a[value] || Time.at(0)   # in case the first scan has not happened
      b_time = b[value] || Time.at(0)   # yet
      a_time <=> b_time
    end.last[value]
  end

  # gives the list of FTP servers _ids depending if they are online or offline
  def self.list_by_status(state)
    FtpServer.collection.find('is_alive' => state).collect {|ftp| ftp['_id']}
  end

  # the index_version is a variable global to all the FTP servers
  def self.index_version
    index_doc = $db['ftp_global'].find_one('name' => 'index_version')
    if index_doc.nil?
      $db['ftp_global'].insert({ 'name' => 'index_version', 'value' => 0 })
      return 0
    else
      return index_doc['value']
    end
  end
  # increment the gobal index_version variable
  def self.incr_index_version
    $db['ftp_global'].update({'name' => 'index_version'}, {'$inc' => {'value' => 1}})
  end


  # handle the ping scan backend
  def self.ping_scan_result(host, is_alive)
    # fist we check if the host is known in the database
    server = self.collection.find_one({'host' => host})
    if server.nil?
      # if the server doesn't exist
      if is_alive
        # but that he is a FTP server
        # then we create it
        # after a quick reverse DNS resolution
        begin
          name = Socket.getaddrinfo(line, 0, Socket::AF_UNSPEC, Socket::SOCK_STREAM, nil, Socket::AI_CANONNAME)[0][2]
        rescue
          name = "anonymous ftp"
        end
        item = {
          :host       => host,
          :name       => name,
          :port       => 21,
          :ftp_type   => 'Unix',
          :ftp_encoding => 'ISO-8859-1',
          :force_utf8  => true,
          :login     => 'anonymous',
          :password  => 'garbage2',
          :ignored_dirs => '. .. .svn',
          :is_alive   => is_alive,
          :last_ping  => Time.now
        }
        self.collection.insert item
      end
    else
      # if the server exists in the database
      # then we update its status
      self.collection.update(
        { "_id" => server["_id"] },
        { "$set" => {
          :is_alive   => is_alive,
          :last_ping  => Time.now
          }
        }
      )
    end
  end

  # this is the method which launch the process to index an FTP server
  def self.get_entry_list(ftp_server ,max_retries = 3)
    require 'net/ftp'
    require 'net/ftp/list'
    require 'iconv'
    require 'logger'
    @max_retries = max_retries.to_i
    # with a value of 1 we will simply ignore charset errors without retry
    @max_retries_get_list = 1
    BasicSocket.do_not_reverse_lookup = true

    # Trying to open ftp server, exit on max_retries
    retries_count = 0
    begin
      @logger = Logger.new(File.dirname(__FILE__) + '/log/spider.log', 0)
      @logger.formatter = Logger::Formatter.new
      @logger.datetime_format = "%Y-%m-%d %H:%M:%S"
      @logger.info("on #{ftp_server['host']} : Trying ftp server #{ftp_server['name']} (id=#{ftp_server['_id']})")
      ftp = Net::FTP.open(ftp_server['host'], ftp_server['login'], ftp_server['password'])
      ftp.passive = true
    rescue => detail
      retries_count += 1
      @logger.error("on #{ftp_server['host']} : Open ftp exception: " + detail.class.to_s + " detail: " + detail.to_s)
      @logger.error("on #{ftp_server['host']} : Retrying #{retries_count}/#{@max_retries}.")
      if (retries_count >= @max_retries)
        @logger.error("on #{ftp_server['host']} : Retry reach max times, now exit.")
        #@logger.close
        exit
      end
      ftp.close if (ftp && !ftp.closed?)
      @logger.error("on #{ftp_server['host']} : Wait 30s before retry open ftp")
      sleep(30)
      retry
    end

    # Trying to get ftp entry-list
    get_list_retries = 0
    begin
      @logger.info("on #{ftp_server['host']} : Server connected")
      start_time = Time.now
      @entry_count = 0
      
      # building the index
      @index_version = FtpServer.index_version
      get_list_of(ftp_server, ftp)

      # updating the time of last scan
      self.collection.update(
        { "_id" => ftp_server["_id"] },
        { "$set" => { :updated_on  => Time.now }
        }
      )
      
      process_time = Time.now - start_time
      @logger.info("on #{ftp_server['host']} : Finish getting list of server " + ftp_server['name'] + " in " + process_time.to_s + " seconds.")
      @logger.info("on #{ftp_server['host']} : Total entries: #{@entry_count}. #{(@entry_count/process_time).to_i} entries per second.")
    rescue => detail
      get_list_retries += 1
      @logger.error("on #{ftp_server['host']} : Get entry list exception: " + detail.class.to_s + " detail: " + detail.to_s)
      @logger.error("on #{ftp_server['host']} : Retrying #{get_list_retries}/#{@max_retries}.")
      raise if (get_list_retries >= @max_retries)
      retry
    ensure
      ftp.close if !ftp.closed?
      @logger.info("on #{ftp_server['host']} : Ftp connection closed.")
      # not the smartiest solution, but closing the log device can be a real issue in a multi-threaded environment
      #@logger.close
    end
  end

private

  

  # get entries under parent_path, or get root entries if parent_path is nil
  def self.get_list_of(ftp_server, ftp, parent_path = nil, parents = [])
    ic = Iconv.new('UTF-8', ftp_server['ftp_encoding']) if ftp_server['force_utf8']
    ic_reverse = Iconv.new(ftp_server['ftp_encoding'], 'UTF-8') if ftp_server['force_utf8']

    retries_count = 0
    begin
      entry_list = parent_path ? ftp.list(parent_path) : ftp.list
    rescue => detail
      retries_count += 1
      @logger.error("on #{ftp_server['host']} : Ftp LIST exception: " + detail.class.to_s + " detail: " + detail.to_s)
      @logger.error("on #{ftp_server['host']} : Ftp LIST exception: the parent_path (if present) was : " + parent_path)
      @logger.error("on #{ftp_server['host']} : Retrying get ftp list #{retries_count}/#{@max_retries}")
      return 0 if (retries_count >= @max_retries_get_list)
      
      reconnect_retries_count = 0
      begin
        ftp.close if (ftp && !ftp.closed?)
        @logger.error("on #{ftp_server['host']} : Wait 30s before reconnect")
        sleep(30)
        ftp.connect(ftp_server['host'])
        ftp.login(ftp_server['login'], ftp_server['password'])
        ftp.passive = true
      rescue => detail2
        reconnect_retries_count += 1
        @logger.error("on #{ftp_server['host']} : Reconnect ftp failed, exception: " + detail2.class.to_s + " detail: " + detail2.to_s)
        @logger.error("on #{ftp_server['host']} : Retrying reconnect #{reconnect_retries_count}/#{@max_retries}")
        raise if (reconnect_retries_count >= @max_retries)
        retry
      end
      
      @logger.error("on #{ftp_server['host']} : Ftp reconnected!")
      retry
    end

    entry_list.each do |e|
      # Some ftp will send 'total nn' string in LIST command
      # We should ignore this line
      next if /^total/.match(e)

      # usefull for debugging purpose
      #puts "#{@entry_count} #{e}"

      if ftp_server['force_utf8']
        begin
          e_utf8 = ic.iconv(e)
        rescue Iconv::IllegalSequence
          @logger.error("on #{ftp_server['host']} : Iconv::IllegalSequence, file ignored. raw data: " + e)
          next
        end
      end
      entry = Net::FTP::List.parse(ftp_server['force_utf8'] ? e_utf8 : e)

      next if ftp_server['ignored_dirs'].include?(entry.basename)

      @entry_count += 1

      begin
        file_datetime = entry.mtime.strftime("%Y-%m-%d %H:%M:%S")
      rescue => detail3
        puts("on #{ftp_server['host']} : strftime failed, exception: " + detail3.class.to_s + " detail: " + detail3.to_s)
        @logger.error("on #{ftp_server['host']} : strftime failed, exception: " + detail3.class.to_s + " detail: " + detail3.to_s)   
        @logger.error("on #{ftp_server['host']} : raw entry: " + e)
      end
      
      #entry_basename = entry.basename.gsub("'","''")
      entry_basename = entry.basename

      # here we build the document
      # that will be inserted in
      # the datastore
      item = {
        :name => entry_basename,
        :parent_path => parent_path,
        :size => entry.filesize,
        :entry_datetime => entry.mtime,
        :directory => entry.dir?,
        :ftp_server_id => ftp_server['_id'],
        :index_version => @index_version+1
      }
      Entry.collection.insert item
      
      if entry.dir?
        ftp_path = (parent_path ? parent_path : '') + '/' +
                          (ftp_server['force_utf8'] ? ic.iconv(entry.basename) : entry.basename)
                          #(ftp_server['force_utf8'] ? ic_reverse.iconv(entry.basename) : entry.basename)
        get_list_of(ftp_server, ftp, ftp_path, parents)
      end
    end
  end


end

