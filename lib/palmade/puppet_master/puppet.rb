module Palmade::PuppetMaster
  class Puppet
    DEFAULT_OPTIONS = {
      :count => 1,
      :nap_time => 1,
      :proc_tag => nil,
      :before_fork => nil,
      :after_fork => nil }

    attr_accessor :count

    attr_reader :workers
    attr_reader :proc_tag
    attr_reader :master_logger

    def initialize(options = { }, &block)
      @options = DEFAULT_OPTIONS.merge(options)

      @nap_time = @options[:nap_time]
      @work_loop = block_given? ? block : nil
      @proc_tag = @options[:proc_tag]

      @before_fork = @options[:before_fork]
      @after_fork = @options[:after_fork]

      @count = @options[:count].to_i
      @workers = { }
    end

    def build!(m, fam)
      unless m.logger.nil?
        @master_logger = m.logger
      end
      # do nothing, i think this should be inherited!
    end

    def post_build(m, fam)
      # do nothing
    end

    def murder_lazy_workers!(m, fam)
      diff = stat = nil
      @workers.dup.each_pair do |wpid, worker|
        stat = begin
          worker.tmp.stat
        rescue => e
          master_logger.warn "worker=#{worker.nr} PID:#{wpid} stat error: #{e.inspect}"
          kill_worker(:QUIT, wpid)
          next
        end
        stat.mode == 0100000 and next
        (diff = (Time.now - stat.ctime)) <= m.timeout and next

        master_logger.error "worker=#{worker.nr} PID:#{wpid} timeout " +
          "(#{diff}s > #{m.timeout}s), killing"

        kill_worker(:KILL, wpid) # take no prisoners for timeout violations
      end
    end

    def kill_each_workers(m, fam, signal)
      @workers.keys.each { |wpid| kill_worker(signal, wpid) }
    end

    def maintain_workers!(m, fam)
      # check if we miss some workers
      (off = @workers.size - @count) == 0 and return
      off < 0 and return spawn_missing_workers(m)

      # check if we have more workers as needed
      @workers.dup.each_pair do |wpid, w|
        w.nr >= @count && kill_worker(:QUIT, wpid) rescue nil
      end

      self
    end

    def spawn_missing_workers(m)
      (0...@count).each do |worker_nr|
        # if a worker exist already, just skip it!
        @workers.values.include?(worker_nr) && next

        worker = Palmade::PuppetMaster::Worker.new(m, self, worker_nr)
        m.fork(worker) do |pid|
          @workers[pid] = worker
        end
      end
    end

    def resign!(m, fam, worker)
      @workers.values.each { |w| w.close }
      @workers.clear
    end

    # placeholder, u can override to do ur own pre- and post- code
    def before_fork(worker)
      @before_fork.call(self, worker) unless @before_fork.nil?
    end

    def after_fork(worker)
      @after_fork.call(self, worker) unless @after_fork.nil?
      GC.start
    end

    # do nothing
    def before_work(worker, ret = nil); end
    def after_work(worker, ret = nil); end

    def work_loop=(proc)
      @work_loop = proc
    end

    def work_loop(worker, ret = nil, &block)
      master_logger.warn "worker #{worker.proc_tag} started: #{$$}"

      # trap(:USR1) {  } do nothing, it should reload logs
      [ :QUIT, :INT ].each { |sig| trap(sig) { worker.stop! } }
      [ :TERM, :KILL ].each { |sig| trap(sig) { exit!(0) } } # instant shutdown

      begin
        loop do
          break unless worker.ok?
          worker.alive!

          # do some work
          if block_given?
            yield(self, worker)
          elsif !@work_loop.nil?
            @work_loop.call(self, worker)
          else
            # do nothing!
          end

          if worker.ok?
            worker.alive!
            sleep(@nap_time)
          else
            break
          end
        end
      rescue Exception => e
        master_logger.error "#{e.class.name}: #{e.message}\n#{e.backtrace.join("\n")}"
      end

      master_logger.warn "worker #{worker.proc_tag} stopped: #{$$}"

      ret
    end

    def stop_work_loop(worker)
      worker.stop!
    end

    def reap!(m, fam, wpid, status)
      if @workers.include?(wpid)
        worker = @workers.delete(wpid) and worker.close
        master_logger.warn "reaped #{status.inspect} worker=#{worker.proc_tag rescue 'unknown'}"
      end
    end

    def kill_worker(signal, wpid)
      begin
        Process.kill(signal, wpid)
      rescue Errno::ESRCH
        worker = @workers.delete(wpid) and worker.close
      end
    end
  end
end
