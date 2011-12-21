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
  FtpServer.collection.find().each do |ftp|
    puts "#{ftp['host']}\t#{ftp['name']}"
  end
when :info
  ftp = FtpServer.collection.find_one({:host => options[:host]})
  ["host", "name", "port","ignored_dirs", "is_alive", "last_ping", "login", "password", "total_files", "total_size", "updated_on", "force_utf8", "ftp_encoding", "ftp_type"].each do |key| 
    puts "#{key.ljust(12)}\t#{ftp[key]}"
  end
when :entries
  ftp = FtpServer.collection.find_one({:host => options[:host]})
  Entry.collection.find({'ftp_server_id' => ftp['_id']}).each do |entry| 
    puts "#{Entry.full_path(entry)}\t#{entry['size']}\t#{entry['entry_datetime']}"
  end
when :name
  FtpServer.collection.update({:host => options[:host]}, {'$set' => {'name' => options[:name]}})
  puts "#{options[:host]}\t#{options[:name]}"
when :delete 
  Entry.collection.remove({'ftp_server_id' => FtpServer.collection.find_one({:host => options[:host]})['_id'] })
  FtpServer.collection.remove({:host => options[:host]})
  puts "Host deleted and entries purged"
else
  puts "Unknown action"
  exit
end

