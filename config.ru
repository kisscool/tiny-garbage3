# vim: set softtabstop=2 shiftwidth=2 expandtab syntax=ruby:

require 'rubygems'
# use Bundler if present
begin
  ENV['BUNDLE_GEMFILE'] = File.join(File.dirname(__FILE__), './Gemfile')
  require 'bundler/setup'
rescue LoadError
end

require File.join(File.dirname(__FILE__), 'app.rb')

run App.new
