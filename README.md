Tiny-Garbage3
=============

Just a little FTP crawler, with a Sinatra based search interface in order to browse the FTP index.
Nothing else, nothing more.

Relationship with the original Tiny-Garbage project(s)
------------------------------------------------------

Tiny-Garbage3 is designed to be the next version of the originals [`Tiny-Garbage2`](http://github.com/kisscool/tiny-garbage2) and [`Tiny-Garbage`](http://github.com/kisscool/tiny-garbage) projects. Those are kepts as different projects, because each major version is a total re-design with different dependencies and goals, that may not be of interest for everybody.

* Tiny-Garbage is designed around a relational database (sqlite, mysql...) and is well suited for indexing little networks
* Tiny-Garbage2 is designed around a non-relational database (MongoDB) and is able to scale to the indexing of several hundred of thousands of files and directories without major performances penalties
* Tiny-Garbage3 is designed around the non-relational in-memory database [`Redis`](http://redis.io) and is able to index easily several millions of files and directories.

Additionaly, Tiny-Garbage3 provides the following changes :

* Lot of bugfixes
* A better strategy for index versioning
* Less dependencies
* Less administration overhead
* A more robust infrastructure
* A blazingly fast new inverted index search system

For this version, we have been heavily inspired by some axioms of the UNIX philosphy : "When in doubt, use bruteforce" and "smart data structures, simple algorithms".

Quick start
-----------

This is how to bootstrap Tiny-Garbage3 if you are in a real hurry (sh compatible syntax as root, quick and dirty configuration) :

	pkg install ruby redis ruby19-gems ruby19-iconv git
	echo 'redis_enable="YES"' >> /etc/rc.conf
	/usr/local/etc/rc.d/redis start
	gem install bundler
	export tinyroot=/usr/local
	git clone http://github.com/kisscool/tiny-garbage3.git $tinyroot/tiny-garbage3
	cd $tinyroot/tiny-garbage3
	bundle install --path vendor
	cp config.rb.sample config.rb
	echo "You must edit config.rb in order to configure Tiny-Garbage3"
	echo "30 * * * * root $tinyroot/tiny-garbage3/scripts/crawler.rb ping" >> /etc/crontab
	echo "0 2 * * * root $tinyroot/tiny-garbage3/scripts/crawler.rb index" >> /etc/crontab

Read below for explanations.

Dependencies
------------

This software assumes you have already setup a Redis database (the default configuration works out of the box) and that ruby and iconv are available.

Required gems are :

* redis
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

For a first try you can just launch "rackup config.ru" (or "bundle exec rackup" if you are using Bundler) in order to test the web UI with the pure ruby Webrick server.
If you want to deploy it in production, you will need to check Unicorn, Thin or Phusion Passenger documentations for more solids options.

### Memory requirements

Redis is a in-memory datastore with persistence on disk. If you don't have enough memory for your needs, you can enable the VM options to use your disk instead. Do it at your own risk as the Redis documentation warns that the use of this feature is discouraged.
You will need around 1.4GB of memory for the storage of 600 000 entries (each file or directory is an individual entry in the database) on a 64bit system.

Screenshots
-----------

Here are some screenshots from a Tiny-Garbage3 deployment transmitted to us by some of our friendly users.

![Search](https://github.com/downloads/kisscool/tiny-garbage2/garbage_1.png)
![Listing](https://github.com/downloads/kisscool/tiny-garbage2/garbage_2.png)


Thanks
------

Thanks to Loic Gomez for the first Garbage Collector, which was so useful back in the days, and thanks to Zouchaoqun's [`ezFtpSearch`](http://github.com/zouchaoqun/ezftpsearch) whose model bootstrapped our early work.

