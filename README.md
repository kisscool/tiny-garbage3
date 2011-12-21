Tiny-Garbage2
=============

Just a little FTP crawler, with a little Sinatra based search interface in order to browse the FTP index.
Nothing else, nothing more.

Relationship with the original Tiny-Garbage project
---------------------------------------------------

Tiny-Garbage2 was designed to be the next version of the original [`Tiny-Garbage`](http://github.com/kisscool/tiny-garbage)
The original goal was to re-implement the backend in MongoDB in order to help it scale past several hundred of thousands of indexed files. Unfortunately we quickly discovered it would definitively break our compatibility with more traditional RDBMS.

The original Tiny-Garbage is already a complete and stable piece of software ready for production, besides everybody does not need or want to jump in the NoSQL bandwagon. So we decided to let the original project continue to live without changing its relational philosophy and to build the NoSQL version as a separate project.

* If you want a pretty solid software based on SQLite or MySQL, with a beautiful and clean object oriented backend : take tiny-garbage.
* If you want an amazingly fast and scalable software based on MongoDB, albeit less beautiful and more experimental : take tiny-garbage2.

Dependencies
------------

This software assumes you have already setup a Mongodb database and that ruby and iconv are available.

Required gems are :

* mongo
* bson_ext
* sinatra
* haml
* sass
* net-ftp-list
* Rack

If you have Bundler installed on your system, you can track down all those dependencies by launching the following command from inside the project directory :

	$ bundle install --path vendor

Install
-------

### The crawler part

Do a clone of the project git repository, install the missing dependencies then create the configuration file by copying config.rb.sample as config.rb and edit it to suit your taste.

Configure your crontab to launch periodically the following commands :

* "$path_to_project/scripts/crawler.rb ping" (with a recommenced frequency of every 10 minutes)
* "$path_to_project/scripts/crawler.rb index" (with a recommended frequency of once a day)


### The Web UI part

For a first try you can just launch "rackup config.ru" in order to test the web UI with the pure ruby Webrick server.
If you want to deploy it in production, you will want to check Unicorn, Thin or Phusion Passenger documentations for more solids options.

Screenshots
-----------

Here are some screenshots from a Tiny-Garbage2 V1 deployment transmitted to us by some of our friendly users.

![Search](https://github.com/downloads/kisscool/tiny-garbage2/garbage_1.png)
![Listing](https://github.com/downloads/kisscool/tiny-garbage2/garbage_2.png)


Thanks
------

Thanks to Loic Gomez for the first Garbage Collector, which was so useful back in the days, and thanks to Zouchaoqun's [`ezFtpSearch`](http://github.com/zouchaoqun/ezftpsearch) whose model bootstrapped our early work.

