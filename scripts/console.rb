#!/usr/bin/env ruby
# vim: set softtabstop=2 shiftwidth=2 expandtab :
# (c) 2010 KissCool & Madtree

# interactive console loaded with the data model

# loading the db model
libs =  " -r irb/completion"
libs << %( -r "#{File.dirname(__FILE__)}/../model.rb")

exec "irb #{libs} --simple-prompt"
