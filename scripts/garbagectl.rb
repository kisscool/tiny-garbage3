#!/usr/bin/env ruby
# vim: set softtabstop=2 shiftwidth=2 expandtab :
# (c) 2011 KissCool & Madtree

# loading the db model
require File.join(File.dirname(__FILE__), '../model.rb')

require 'optparse'

###########################################################
################### PARSING

options = {
  :host => "",
  :name => "",
  :action => :list
}

OptionParser.new do |opts|
  opts.banner = "*** Tiny-Garbage DB Manipulation Tool***\n\nUsage: #{$0.split("/").last} [options]"

  opts.on("-l", "--list", "List all the known hosts") do |list|
    options[:action] = :list
  end
  opts.on("-H", "--host IP_ADRESS", "IP adress of a known host you wish to manipulate") do |host|
    options[:host] = host
  end
  opts.on("-i", "--info", "Show informations about the selected host") do |info|
    options[:action] = :info
  end
  opts.on("-e", "--entries", "Show file entries of the selected host") do |entries|
    options[:action] = :entries
  end
  opts.on("-n", "--name NAME", "Rename the selected host") do |name|
    options[:action] = :name
    options[:name] = name
  end
  opts.on("-d", "--delete", "Delete the selected host") do |del|
    options[:action] = :delete
  end
  opts.on("-s", "--stats", "Statistics on the database") do |stat|
    options[:action] = :stats
  end


end.parse!

# check for required options
if [:delete, :info, :entries, :name].include?(options[:action]) and options[:host] == ""
  puts "Missing option --host for this action"
  exit
end


###########################################################
################### ACTIONS

case options[:action]
when :list
  ftp_list = FtpServer.ftp_list
  ftp_list.each do |ftp|
    puts "#{ftp[0]}\t#{ftp[1]}"
  end
when :info
  ftp = FtpServer.ftp_info(options[:host])
  ['host', 'name', 'number of files', 'size', 'last scan', 'is alive'].each_with_index do |item, index|
    puts "#{item.ljust(12)}\t#{ftp[index]}"
  end
when :entries
  entry_list = Entry.list(options[:host])
  entry_list.each do |entry|
    puts "#{entry[0]}\t#{entry[1]}\t#{entry[2]}"
  end
when :name
  FtpServer.rename(options[:host], options[:name])
  puts "#{options[:host]}\t#{options[:name]}"
when :delete
  FtpServer.remove(options[:host])
  puts "Host deleted and entries purged"
when :stats
  info = $db.info
  ['used_memory_human','db0','connected_clients'].each do |item|
    puts "#{item.ljust(18)}\t#{info[item]}"
  end
else
  puts "Unknown action"
  exit
end

