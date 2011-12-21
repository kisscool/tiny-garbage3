#!/usr/bin/env ruby
# vim: set softtabstop=2 shiftwidth=2 expandtab :
# (c) 2010 KissCool & Madtree

# loading the db model
require File.join(File.dirname(__FILE__), '../model.rb')


###########################################################
################### PARSING

banner = <<"EOF"
*** Tiny-Garbage Renamer ***

Gives explicit names to your FTPs

Usage: #{$0.split("/").last} [-h] ip_adress [hostname]
  arguments :
   * ip_adress  : IP adress of a know host, already detected by Tiny-Garbage
   * hostname : name you want to give to the host
EOF

if ARGV == [] or ARGV[0] =~ /-h|--help/
  puts banner
  exit
end

ip_adress = ARGV[0]
hostname = ARGV[1]


if hostname == nil
  name = FtpServer.collection.find_one({:host => ip_adress})['name']
  puts "#{ip_adress} : #{name}"
else
  FtpServer.collection.update({:host => ip_adress}, {'$set' => {'name' => hostname}})
  puts "#{ip_adress} : #{hostname}"
end

