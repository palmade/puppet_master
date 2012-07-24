module Palmade::PuppetMaster
  module Puppets
    class Base
      DEFAULT_OPTIONS = {
        :count => 1,
        :nap_time => 1,
        :proc_tag => nil,
        :disable_workloop => false,
        :before_fork => nil,
        :after_fork => nil }

        attr_accessor :count

        attr_reader :workers
        attr_reader :proc_tag
        attr_reader :master_logger
        attr_accessor :master
        attr_accessor :family

        def initialize(master = nil, family = nil, options = { }, &block)
          if master.is_a? Palmade::PuppetMaster::Master
            @master = master
          else
            warn "[DEPRECATION] `master` should be passed on puppet's initialization."
            @master = nil
            options = master
          end

          @family = family
          @options = DEFAULT_OPTIONS.merge(options)

          @nap_time = @options[:nap_time]
          @work_loop = block_given? ? block : nil
          @proc_tag = @options[:proc_tag]

          @before_fork = @options[:before_fork]
          @after_fork = @options[:after_fork]

          @count = @options[:count].to_i
          @workers = { }
        end

        def build!(master = nil, family = nil)
          deprecation_warning_ancestor(master, family) if master or family

          unless @master.logger.nil?
            @master_logger = @master.logger
          end
          # do nothing, i think this should be inherited!
        end

        def post_build
          # do nothing
        end

        def murder_lazy_workers!
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
            (diff = (Time.now - stat.ctime)) <= @master.timeout and next

            master_logger.error "worker=#{worker.nr} PID:#{wpid} timeout " +
            "(#{diff}s > #{@master.timeout}s), killing"

            kill_worker(:KILL, wpid) # take no prisoners for timeout violations
          end
        end

        def all_workers_checked_in?
          return unless (@workers.size - @count) == 0

          @workers.dup.each_value do |worker|
            worker.checked_in? and next
            return false
          end
          return true
        end

        def kill_each_workers(signal)
          @workers.keys.each { |wpid| kill_worker(signal, wpid) }
        end

        def maintain_workers!
          # check if we miss some workers
          (off = @workers.size - @count) == 0 and return
          off < 0 and return spawn_missing_workers

          # check if we have more workers as needed
          @workers.dup.each_pair do |wpid, w|
            w.nr >= @count && kill_worker(:QUIT, wpid) rescue nil
          end

          self
        end

        def spawn_missing_workers
          (0...@count).each do |worker_nr|
            # if a worker exist already, just skip it!
            @workers.values.include?(worker_nr) && next

            worker = Palmade::PuppetMaster::Worker.new(@master, self, worker_nr)
            @master.fork(worker) do |pid|
              @workers[pid] = worker
            end
          end
        end

        def resign!(worker)
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

        def reap!(wpid, status)
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

        private
        def deprecation_warning_ancestor(master, family)
          warn "[DEPRECATION] `master` and `family` should be passed on initialization"
          @master = master
          @family = family
        end
    end
  end
end
