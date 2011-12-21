# vim: set softtabstop=2 shiftwidth=2 expandtab :
# (c) 2010 KissCool & Madtree

require 'rubygems'
require 'sinatra'
require 'haml'
require 'sass'

# helpers
require File.join(File.dirname(__FILE__), '/lib/helpers.rb')


# entry point
class App < Sinatra::Base
  helpers MyHelpers

  set :static, true
  set :public_folder, 'public/'

  # loading the db model
  require File.join(File.dirname(__FILE__), 'model.rb')

  # some kind of magic
  before do
    content_type :html, 'charset' => 'utf-8'
  end

  ############ Indexes
  #
  get '/' do
    haml :index
  end

  get '/search' do
    # check our default arguments are valid
    params[:query] ||= ''
    params[:page]  ||= 1
    params[:order] ||= 'ftp_server_id.ascending'
    
    # execute the search method
    @page_count, @results = Entry.complex_search(
      format_query(params[:query]), 
      params[:page].to_i, 
      params[:order],
      object_to_boolean(params[:online])
    )

    # and smoke it
    haml :index
  end

  # stats
  get '/stats' do
    @total_count = FtpServer.collection.count
    @total_last_ping = FtpServer.global_last(:last_ping)
    @total_last_scan = FtpServer.global_last(:updated_on)
    @total_number_of_files = Entry.collection.find('index_version' => FtpServer.index_version, :directory => false).count
    @total_size = FtpServer.added_total_size
    haml :stats
  end

  # FTP listing
  get '/list' do
    @ftp_list = FtpServer.collection.find
    haml :list
  end

  ############ Misc
  #

  # this is the new shit, baby
  get '/stylesheet.css' do
    content_type 'text/css', :charset => 'utf-8'
    sass :stylesheet
  end

end 
