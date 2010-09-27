module Palmade::PuppetMaster
  class Master
    DEFAULT_OPTIONS = {
      :timeout => 45,
      :nap_time => 3,
      :proc_tag => nil,
      :proc_name => $0.clone,
      :proc_argv => ARGV.clone
    }

    QUEUE_SIGS = [ :WINCH, :QUIT, :INT, :TERM, :USR1, :USR2, :HUP, :TTIN, :TTOU ]

    attr_accessor :family
    attr_accessor :logger
    attr_accessor :timeout

    attr_reader :master_pid
    attr_reader :services
    attr_reader :reserved_ports
    attr_reader :forks

    attr_reader :proc_name
    attr_reader :proc_argv
    attr_accessor :proc_tag

    attr_reader :listeners

    def initialize(options = { })
      @options = DEFAULT_OPTIONS.merge(options)
      @family = nil
      @sig_queue = [ ]

      @proc_name = @options[:proc_name]
      @proc_argv = @options[:proc_argv]
      @proc_tag = @options[:proc_tag]

      @respawn = true
      @stopped = nil

      @timeout = @options[:timeout]
      @nap_time = @options[:nap_time]

      @services = { }
      @reserved_ports = ::Set.new
      @listeners = { }

      @unjoin = nil
      @forks = [ ]

      @reset_application_callbacks = [ ]
      @shutdown_application_callbacks = [ ]
    end

    def fork(handler, priority = false, &block)
      if priority
        forks.unshift([ handler, block ])
      else
        forks.push([ handler, block ])
      end
    end

    def perform_forks
      @forks.each do |f|
        handler = f[0]
        block = f[1]

        fid = handler.fork
        if fid.nil?
          $stdin.sync = $stdout.sync = $stderr.sync = true

          # we're in the child process
          unjoin(handler)
          return fid
        else
          block.call(fid)
        end
      end unless @forks.empty?

      @forks.size
    ensure
      @forks.clear
    end

    def close_services
      @services.each_value { |s| s.close }
    end

    def reset_services
      @services.each_value { |s| s.reset }
    end

    def boot_services
      @services.each_value { |s| s.boot }
    end

    def use_service(type, options = { })
      case type
      when :cache
        raise "Cache service already exist!" if @services.include?(:cache)
        @services[:cache] = Palmade::PuppetMaster::ServiceCache.new(self, :cache, options)
      when :queue
        raise "Queue service already exist!" if @services.include?(:queue)
        @services[:queue] = Palmade::PuppetMaster::ServiceQueue.new(self, :queue, options)
      when :redis
        raise "Redis service already exist!" if @services.include?(:redis)
        @services[:redis] = Palmade::PuppetMaster::ServiceRedis.new(self, :redis, options)
      when :tokyo_cabinet
        raise "Tokyo Cabinet service already exist!" if @services.include?(:tokyo_cabinet)
        @services[:tokyo_cabinet] = Palmade::PuppetMaster::ServiceTokyoCabinet.new(self, :tokyo_cabinet, options)
      else
        raise "Unknown service type"
      end
    end

    def single_family!(options = { }, &block)
      @family = Palmade::PuppetMaster::Family.new(options)
    end

    def start
      if logger.nil?
        if Palmade::PuppetMaster.logger.nil?
          @logger = Logger.new($stderr)
        else
          @logger = Palmade::PuppetMaster.logger
        end
      end
      verify_if_were_ready!

      if GC.respond_to?(:copy_on_write_friendly=)
        logger.warn "Turning on copy-on-write friendly (REE patches)"
        GC.copy_on_write_friendly = true
      end

      @master_pid = $$
      logger.warn "master started: #{@master_pid}"
      if @proc_tag.nil?
        set_proc_name "master"
      else
        set_proc_name "master[#{@proc_tag}]"
      end

      # refresh gem list
      if defined?(Gem) && Gem.respond_to?(:refresh)
        Gem.refresh
      end

      # let's boot our services
      boot_services

      # let's build the family of puppets
      family.build!(self)

      # let's create our listeners
      create_listeners!

      self
    end

    # join, monitors the families and it's pups
    # receives signals, and maintain worker count
    # also purges lazy workers
    def join
      return if @stopped

      @sig_queue.clear
      setup_traps
      EventMachine.run do
        EventMachine.epoll rescue nil
        EventMachine.kqueue rescue nil

        wakeup!
      end
    ensure
      clear_traps(true)
      trap(:CHLD, 'DEFAULT')

      if @stopped == :UNJOIN && !@unjoin.nil?
        if @unjoin.is_a?(Palmade::PuppetMaster::Worker)
          logger.warn "joining #{@unjoin.proc_tag} (#{@unjoin.class.name})"
        else
          logger.warn "joining #{@unjoin.class.name}"
        end

        begin
          if @unjoin.respond_to?(:work)
            @unjoin.work
          elsif @unjoin.respond_to?(:call)
            @unjoin.call
          else
            raise "Unsupported unjoin handler passed, got: #{@unjoin.class.name}"
          end
        rescue Exception => e
          logger.error "Unhandled exception when trying to join handler #{e.inspect}."
          logger.error e.backtrace.join("\n")
        end

        close_listeners!

        @unjoin = nil
      else
        logger.warn "shutting down..."

        # probably, we got an exception, that unravled our event machine
        if @stopped.nil?
          logger.error "woops!, we shouldn't be here, unless explicitly stopped!"
        end

        stop!(@stopped)
      end
    end

    def unjoin(handler)
      @unjoin = handler
      @stopped = :UNJOIN

      # let's unjoin as soon as possible!
      EventMachine.stop_event_loop if EventMachine.reactor_running?
    end

    def set_proc_name(tag)
      pn = ([ @proc_name, tag ]).concat(@proc_argv).join(' ') + "\0"
      $0 = pn
    end

    def reopen_logger
      if logger.respond_to?(:reopen)
        logger.reopen
      elsif logger.respond_to?(:reconnect)
        logger.reconnect
      elsif logger.respond_to?(:reset)
        logger.reset
      else
        # do nothing!
      end
    end

    # a custom method, that calls a pre-defined application block
    # reset application is called from a worker, to tell it to re-set,
    # right after forking
    def reset_application!(worker)
      unless @reset_application_callbacks.empty?
        @reset_application_callbacks.each do |c|
          c.call(worker, self)
        end
      end
    end

    def on_reset_application(&block)
      @reset_application_callbacks.push(&block)
    end

    # this method is called from the newly forked worker process
    # we clean everything related to the other workers here
    def resign!(worker = nil, new_proc_name = nil)
      if new_proc_name.nil?
        self.set_proc_name("worker[#{worker.proc_tag}]")
      else
        self.set_proc_name(new_proc_name)
      end
      family.resign!(self, worker)
    end

    # a custom method, that calls a defined block
    # is called when a service exec, and we need to shutdown
    def shutdown_application!(service)
      unless @shutdown_application_callbacks.empty?
        @shutdown_application_callbacks.each do |c|
          c.call(service, self)
        end
      end
    end

    def on_shutdown_application(&block)
      @shutdown_application_callbacks.push(&block)
    end

    # shutdown master process, in case we are forking to an 'unsupported child'
    def shutdown!
      close_listeners!
      @logger.close
    end

    def listen(lk, *listen)
      options = listen.last.is_a?(Hash) ? listen.pop : { }
      listen = listen.flatten

      raise ArgumentError, "Listener set #{lk || 'default'} already initialized" if @listeners.include?(lk)
      @listeners[lk] = [ ]
      listen.each do |lspec|
        @listeners[lk].push(create_listener(lspec))
      end
      @listeners[lk]
    end

    def detach_listeners_from_master
      @listeners.each do |lk, ls|
        ls.each do |sock|
          sock.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)
        end
      end
    end

    protected

    def create_listeners!
      raise ArgumentError, "Listeners already initialized" unless @listeners.empty?

      # supported listener specs:
      # - 127.0.0.1:80
      # - 80 (port only, defaults to localhost)
      # - /path/unix
      unless @options[:listen].nil? || @options[:listen].empty?
        case @options[:listen]
        when Hash, Palmade::PuppetMaster::Config
          @options[:listen].each do |lk, ls|
            lk = lk.to_sym
            lk = nil if lk == :default

            listen(lk, ls)
          end
        when Array
          listen(nil, @options[:listen])
        else
          raise ArgumentError, "Unsupported listener specs: #{@options[:listen].inspect}"
        end
      end
    end

    def create_listener(lspec)
      logger.warn "Creating listener: #{lspec}"
      Palmade::PuppetMaster::SocketHelper.listen(lspec)
    end

    def close_listeners!
      @listeners.each do |lk, ls|
        ls.each do |sock|
          sock.close rescue nil
        end
        ls.clear
      end
      @listeners.clear
    end

    def stop!(graceful = true)
      case graceful
      when true
        @stopped = :QUIT
      when false
        @stopped = :TERM
      when Symbol, String
        @stopped = graceful.to_sym
      else
        @stopped = :QUIT
      end

      if EventMachine.reactor_running?
        EventMachine.stop_event_loop
      else
        # now, let's kill all workers
        kill_all_workers(@stopped)

        # now, let's kill all our services
        kill_all_services(@stopped)

        # close listeners, if we have any?
        close_listeners!
      end
    end

    def kill_all_services(signal)
      step = 0.2
      @services.each_value { |s| s.kill(signal) }
      sleep(step)
      reap_dead_children!

      # let's wait until all workers are dead, or we've timed out!
      timeleft = @timeout
      until all_services_dead?
        sleep(step)
        reap_dead_children!
        (timeleft -= step) > 0 and next
        @services.each_value { |s| s.kill(:KILL) }
      end
    end

    def all_services_dead?
      all = true
      @services.each_value do |s|
        all = false if s.alive?
      end
      all
    end

    def maintain_services!
      @services.each_value do |s|
        unless s.check_alive? || s.disabled?
          s.start
        end
      end
    end

    def kill_all_workers(signal)
      step = 0.2
      family.kill_each_workers self, signal
      sleep(step)
      reap_dead_children!

      # let's wait until all workers are dead, or we've timed out!
      timeleft = @timeout
      until family.all_workers_dead?(self)
        sleep(step)
        reap_dead_children!
        (timeleft -= step) > 0 and next
        family.kill_each_workers self, :KILL
      end
    end

    def do_some_work
      return if @stopped

      begin
        reap_dead_children!

        case @sig_queue.shift
        when nil
          family.murder_lazy_workers!(self)
          maintain_services!
          family.maintain_workers!(self) if @respawn
        when :QUIT, :INT # graceful shutdown
          stop!
        when :TERM # immediate shutdown
          stop!(false)
        when :USR1 # TODO: rotate logs
          #logger.info "master reopening logs..."
          #Unicorn::Util.reopen_logs
          #logger.info "master done reopening logs"
          #kill_each_worker(:USR1)
        when :USR2 # TODO: exec binary, stay alive in case something went wrong
          # reexec
        when :WINCH # TODO: kills all workers, but keep the master
          if Process.ppid == 1 || Process.getpgrp != $$
            @respawn = false
            #logger.info "gracefully stopping all workers"
            family.kill_each_workers self, :QUIT
            kill_all_services :QUIT
          else
            #logger.info "SIGWINCH ignored because we're not daemonized"
          end
        when :TTIN # TODO:
          # self.worker_processes += 1
        when :TTOU # TODO:
          # self.worker_processes -= 1 if self.worker_processes > 0
        when :HUP
          @respawn = true
          #if config.config_file
          #  load_config!
          #  redo # immediate reaping since we may have QUIT workers
          #else # exec binary and exit if there's no config file
          #  logger.info "config_file not present, reexecuting binary"
          #  reexec
          #  break
          #end
        end
      #rescue Errno::EINTR
        #retry
      rescue Object => e
        logger.error "Unhandled master loop exception #{e.inspect}."
        logger.error e.backtrace.join("\n")
      end

      unless @stopped
        unless @sig_queue.empty?
          wakeup!
        else
          nforks = perform_forks

          # forked childs return a nil nforks
          unless nforks.nil?
            take_a_nap!
          end
        end
      end
    end

    def cancel_nap!
      unless @nap_timer.nil?
        EventMachine.cancel_timer(@nap_timer)
        @nap_timer = nil
      end
    end

    def take_a_nap!
      @nap_timer = EventMachine.add_timer(@nap_time) { @nap_timer = nil; wakeup! }
    end

    def wakeup!
      if EventMachine.reactor_running?
        cancel_nap!
        EventMachine.next_tick { do_some_work }
      else
        do_some_work
      end
    end

    def setup_traps
      QUEUE_SIGS.each { |sig| trap_deferred(sig) }
      trap(:CHLD) { |sig_nr| wakeup! }
    end

    def clear_traps(default = false)
      QUEUE_SIGS.each { |sig| trap(sig, default ? 'DEFAULT' : nil) }
    end

    def trap_deferred(signal)
      trap(signal) do |sig_nr|
        logger.warn "got signal: #{signal}"

        if @sig_queue.size < 5
          @sig_queue << signal
          wakeup!
        else
          # ignoring, signal, too many in queue at the moment
          logger.error "ignoring SIG#{signal}, queue=#{@sig_queue.inspect}"
        end
      end
    end

    def reap_dead_children!
      begin
        loop do
          # check if we have any child process that died
          wpid, status = Process.waitpid2(-1, Process::WNOHANG)
          wpid or break

          family.reap!(self, wpid, status)
          services.each_value { |s| s.reap!(self, wpid, status) }
        end
      rescue Errno::ECHILD
      end
    end

    def verify_if_were_ready!
      raise "Please specify the family of puppets to run" if @family.nil?
      raise "Must specify a main puppet to run" if @family[nil].nil?
    end
  end
end
