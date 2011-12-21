#!/usr/bin/env ruby
# vim: set softtabstop=2 shiftwidth=2 expandtab :
# (c) 2010 KissCool & Madtree

require 'shellwords'
require 'rack'
require 'uri'
require 'iconv'

module MyHelpers
  include Rack::Utils
  alias_method :h, :escape_html

  # convert a raw string in UTF8 in a valid URL
  def url_utf8(raw_url)
    URI::escape Iconv.new('latin1', 'utf-8').iconv(raw_url)
  end

  # converions of datetimes in various output format strings
  def human_date(datetime)
    datetime.strftime('%d/%m/%Y').gsub(/ 0(\d{1})/, ' \1')
  end
  def human_time(datetime)
    return '' if datetime.nil?
    datetime.strftime('%d/%m/%Y %H:%M').gsub(/ 0(\d{1})/, ' \1')
  end
  def rfc_date(datetime)
    datetime.strftime("%Y-%m-%dT%H:%M:%SZ") # 2003-12-13T18:30:02Z
  end

  # convert various objects in boolean
  # especially useful to convert "true" and "false" in true and false
  def object_to_boolean(value)
    return [true, 'true', 1, '1', 'T', 't'].include?(value.class == String ? value.downcase : value)
  end

  # handy to generate only a partial html view
  def partial(page, locals={})
    haml page, {:layout => false}, locals
  end

  # prepare a string to be used as a search query
  # eg. '"un espace" .flac' --> 'un\ espace.*\.flac'
  def format_query(query='')
    tab = Shellwords.shellwords query
    tab.collect! {|word| Regexp.quote(word)}
    tab.join(".*")
  end

  # convert byte size in B, KB, MB.. human readable size
  # inspired from Actionpack method
  STORAGE_UNITS = ['B', 'KB', 'MB', 'GB', 'TB']
  def number_to_human_size(number)
    return nil if number.nil?
    return "0 B" if number == 0
    max_exp  = STORAGE_UNITS.size - 1
    number   = Float(number)
    exponent = (Math.log(number) / Math.log(1024)).to_i # Convert to base 1024
    exponent = max_exp if exponent > max_exp # we need this to avoid overflow for the highest unit
    number  /= 1024 ** exponent

    "%n %u".gsub(/%n/, ((number * 100).round.to_f / 100).to_s).gsub(/%u/, STORAGE_UNITS[exponent])
  end
  
  # method to calculate what pages must be shown for a search
  def pager( page_count, page_current )
    display = [10, page_count].min
    return (1..display) if display < 10
    return (1..10) if page_current < 6
    return ((page_count-10)..page_count) if (page_count - page_current) < 5
    return ((page_current-5)..page_current+5)
  end

end
