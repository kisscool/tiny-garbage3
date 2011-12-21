#!/usr/bin/env ruby
# vim: set softtabstop=2 shiftwidth=2 expandtab :
# created from the gserver class

require 'thread'

class ThreadPool
  def initialize(max_size)
    @pool = []
    @max_size = max_size
    @pool_mutex = Mutex.new
    @pool_cv = ConditionVariable.new
  end

  def dispatch(*args)
    Thread.new do
      # Wait for space in the pool.
      @pool_mutex.synchronize do
        while @pool.size >= @max_size
          print "Pool is full; waiting to run #{args.join(',')}?\n" if $DEBUG
          # Sleep until some other thread calls @pool_cv.signal.
          @pool_cv.wait(@pool_mutex)
        end
      end
      @pool << Thread.current
      begin
        yield(*args)
      rescue => e
        exception(self, e, *args)
      ensure
        @pool_mutex.synchronize do
          # Remove the thread from the pool.
          @pool.delete(Thread.current)
          # Signal the next waiting thread that there's a space in the pool.
          @pool_cv.signal
        end
      end
    end
  end

  def shutdown
    @pool_mutex.synchronize { @pool_cv.wait(@pool_mutex) until @pool.empty? }
  end

  def exception(thread, exception, *original_args)
    # Subclass this method to handle an exception within a thread.
    puts "Exception in thread #{thread}: #{exception}"
  end

end
