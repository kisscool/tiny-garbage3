#!/usr/bin/env ruby
# vim: set softtabstop=2 shiftwidth=2 expandtab :
# (c) 2010 KissCool & Madtree

# requires
require 'net/ftp'
require 'logger'
require 'ping'
# loading the db model
require File.join(File.dirname(__FILE__), '../model.rb')
# loading our threadpool library
require File.join(File.dirname(__FILE__), '../lib/threadpool.rb')

###########################################################
################### CONFIGURATION

@options = {
  :action   => '',
  :networks => NETWORKS || '', # we use the constant in config.rb
}

###########################################################
################### CORE CODE

# === Index ===

# this cron job will attempt to crawl each FTP server listed
# in the database
# the recommended frequency for this job is once a day
#
# a possible future optimization would be multi-threading

def index
  # we prepare the threadpool
  pool = ThreadPool.new(5)

  # we take note of offline nodes _ids
  ftp_offline = FtpServer.list_by_status(false)

  # then we iterate on online ones
  FtpServer.collection.find({'is_alive' => true}).each do |ftp|
    # we use thread in order to speed up the process
    pool.dispatch(ftp) do |ftp|
      begin
        # scan the following ftp
        FtpServer.get_entry_list ftp
      rescue => detail
        puts "Exception on host " + ftp['host'] + ", exception: " + detail.class.to_s + " detail: " + detail.to_s
      end
    end
  end

  # we close the threadpool
  pool.shutdown
  # we purge old entries
  Entry.purge ftp_offline
  # then we calculate total sizes and total of files for every FTP
  FtpServer.calculate_total_sizes
  FtpServer.calculate_total_number_of_files
  # and finaly we rebuild indexes
  Entry.collection.create_index('name', :background => true)
end


# === Ping ===

# expand networks in an array of hosts
# eg. "10.2.0.* 10.3.0.1" --> ["10.2.0.1", "10.2.0.2", ..., "10.3.0.1"]
def expand_network(networks)
  # we split the string
  expanded_ip_list = networks.split(" ").collect do |network|
    if network.include? '*'
      # if an adress contains a '*' character we replace it
      (1..254).collect do |num|
        network.gsub(/\*/, num.to_s)
      end
    else
      # else we don't alter it
      network
    end
  end
  # ultimately we want a one dimensional array
  expanded_ip_list.flatten
end

# check if an host is alive on the TCP port 21 (2 second timeout)
def ping_tcp(ip)
  Ping.pingecho(ip, 2, 21)
end

# check if we can make an FTP connexion with an host
def ping_ftp(ip)
  #puts ip
  @logger.info("on #{ip} : Trying alive host #{ip} for FTP connexion}")
  # we check if its FTP port is open
  retries_count = 0
  begin
    ftp = Net::FTP.open(ip, "anonymous", "garbage")
    # if the FTP port is responding, then we update
    # the database
    if ftp && !ftp.closed?
      @logger.info("on #{ip} : Host #{ip} did accept FTP connexion")
      ftp.close
      return true
    end
  rescue => detail
    # if it didn't accept connexion, we retry
    retries_count += 1
    if (retries_count >= @max_retries)
      # if we surpass @max_retries, then the host is
      # not considered as an FTP host
      @logger.info("on #{ip} : Host #{ip} didn't accept FTP connexion")
      return false
    else
      sleep(10)
      retry
    end
  ensure
    ftp.close if (ftp && !ftp.closed?)
  end
end

# this cron job will attempt to ping an IP range with the 
# UNIX utility 'fping'
# the recommenced frequency for this job is one every 
# 10 minutes for a little network, or once an hour for a
# big network

def ping
  # we get a list of hosts to check
  expanded_ip_list = expand_network(@options[:networks])

  # static configs
  @max_retries = 3
  BasicSocket.do_not_reverse_lookup = false
  @logger = Logger.new(File.join(File.dirname(__FILE__), '../log/ping.log'), 'monthly')
  @logger.formatter = Logger::Formatter.new
  @logger.datetime_format = "%Y-%m-%d %H:%M:%S"

  # we prepare the threadpool
  pool = ThreadPool.new(30)

  # for each host we launch one TCP ping
  # then we check the FTP connexion if the host
  # is alive
  expanded_ip_list.each do |ip|
    # we use thread in order to speed up the process
    pool.dispatch(ip) do |ip|
      if ping_tcp(ip)   # first we check if the host is alive
        if ping_ftp(ip) # then we check the FTP connexion
          FtpServer.ping_scan_result(ip, true)
          next
        end
      end
      FtpServer.ping_scan_result(ip, false)
    end
  end

  # we close the threadpool
  pool.shutdown

  # and the logging facility
  @logger.close
end




###########################################################
################### PARSING

banner = <<"EOF"
*** Tiny-Garbage Crawler ***

Ping or index your FTPs

Usage: #{$0.split("/").last} [-h] { ping [networks] | index }
  actions :
   * ping  : check if hosts in a network are alive and open to FTP
   * index : crawl known FTP servers and index their content
  options :
   * networks : list of networks, eg. "10.2.0.* 10.3.0.1"
EOF

cmd = ARGV.shift
case cmd
when "index"
  @options[:action] = cmd
when "ping"
  @options[:action]   = cmd
  @options[:networks] =  ARGV.join " " if ARGV != []
else
  puts banner
  exit
end

### here we run the code
case @options[:action]
when "ping"
  ping
when "index"
  index
else
  puts banner
  exit
end

