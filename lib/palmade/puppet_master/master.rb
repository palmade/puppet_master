module Palmade::PuppetMaster
  class Master
    DEFAULT_OPTIONS = {
      :timeout => 45,
      :nap_time => 3,
      :proc_tag => nil,
      :proc_name => $0.clone,
      :proc_argv => ARGV.clone
    }

    SELF_PIPE = []

    QUEUE_SIGS = [ :WINCH, :QUIT, :INT, :TERM, :USR1, :USR2, :HUP, :TTIN, :TTOU ]

    attr_accessor :family
    attr_accessor :logger
    attr_accessor :timeout

    attr_reader :pid
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

      @forks = [ ]

      @reset_application_callbacks = [ ]
      @shutdown_application_callbacks = [ ]

      if logger.nil?
        if Palmade::PuppetMaster.logger.nil?
          @logger = Logger.new($stderr)
        else
          @logger = Palmade::PuppetMaster.logger
        end
      end
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
      when :redis
        raise "Redis service already exist!" if @services.include?(:redis)
        @services[:redis] = Palmade::PuppetMaster::ServiceRedis.new(self, :redis, options)
      else
        raise "Unknown service type"
      end
    end

    def single_family!(options = { }, &block)
      @family = Palmade::PuppetMaster::Family.new(options)
    end

    def start
      create_listeners!

      init_self_pipe!

      verify_if_were_ready!

      setup_traps

      if GC.respond_to?(:copy_on_write_friendly=)
        logger.warn "Turning on copy-on-write friendly (REE patches)"
        GC.copy_on_write_friendly = true
      end

      @pid = $$
      logger.warn "master started: #{@pid}"
      if @proc_tag.nil?
        set_proc_name "master"
      else
        set_proc_name "master[#{@proc_tag}]"
      end

      if defined?(Gem) && Gem.respond_to?(:refresh)
        Gem.refresh
      end

      boot_services

      family.build!(self)

      self
    end

    # join, monitors the families and it's pups
    # receives signals, and maintain worker count
    # also purges lazy workers
    def join
      return if @stopped

      @sig_queue.clear

      do_some_work
    end

    def unjoin(handler)
      @stopped = :UNJOIN

      clear_traps(false)
      trap(:CHLD, 'DEFAULT')
      @sig_queue.clear

      if handler.is_a?(Palmade::PuppetMaster::Worker)
        logger.warn "joining #{handler.proc_tag} (#{handler.class.name})"
      else
        logger.warn "joining #{handler.class.name}"
      end

      begin
        if handler.respond_to?(:work)
          handler.work
        elsif handler.respond_to?(:call)
          handler.call
        else
          raise "Unsupported unjoin handler passed, got: #{handler.class.name}"
        end
      rescue Exception => e
        logger.error "Unhandled exception when trying to join handler #{e.inspect}."
        logger.error e.backtrace.join("\n")
      end

      close_listeners!
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
      logger.warn 'Shutting down.'

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

      # now, let's kill all workers
      kill_all_workers(@stopped)

      # now, let's kill all our services
      kill_all_services(@stopped)

      # close listeners, if we have any?
      close_listeners!
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
      begin
        reap_dead_children!

        case @sig_queue.shift
        when nil
          family.murder_lazy_workers!(self)
          maintain_services!
          family.maintain_workers!(self) if @respawn
          perform_forks unless @stopped
          take_a_nap!
        when :QUIT, :INT # graceful shutdown
          stop!
          break
        when :TERM # immediate shutdown
          stop!(false)
          break
        when :WINCH # TODO: kills all workers, but keep the master
          if Process.ppid == 1 || Process.getpgrp != $$
            @respawn = false
            family.kill_each_workers self, :QUIT
            kill_all_services :QUIT
          end
        when :HUP
          @respawn = true
        end
      rescue Object => e
        logger.error "Unhandled master loop exception #{e.inspect}."
        logger.error e.backtrace.join("\n")
      end while true
    end

    def take_a_nap!(sec = @nap_time)
      IO.select([ SELF_PIPE[0] ], nil, nil, sec) or return
      SELF_PIPE[0].read_nonblock(11)
    end

    def wakeup!
      SELF_PIPE[1].write_nonblock('.')
    end

    def setup_traps
      QUEUE_SIGS.each { |sig| trap_deferred(sig) }
      trap(:CHLD)     { wakeup! }
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
          # check if we have any child process that died
          wpid, status = Process.waitpid2(-1, Process::WNOHANG)
          wpid or break

          family.reap!(self, wpid, status)
          services.each_value { |s| s.reap!(self, wpid, status) }
      rescue Errno::ECHILD
        break
      end while true
    end

    def verify_if_were_ready!
      raise "Please specify the family of puppets to run" if @family.nil?
      raise "Must specify a main puppet to run" if @family[nil].nil?
    end

    private

    def init_self_pipe!
      SELF_PIPE.each { |io| io.close rescue nil }
      SELF_PIPE.replace(IO.pipe)
      SELF_PIPE.each { |io| io.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC) }
    end
  end
end
