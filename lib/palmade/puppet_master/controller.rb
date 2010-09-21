module Palmade::PuppetMaster
  class Controller
    class PidFileExist < RuntimeError; end

    def initialize(proc_name, proc_argv, command, arguments, config)
      @proc_name = proc_name
      @proc_argv = proc_argv

      @command = command
      @arguments = arguments

      @config = config
      @configurator = nil

      @logger = Logger.new($stderr)
      @pid_file = @config[:pid_file]

      @kill_timeout = 60
    end

    def doit!
      case @command
      when "start"
        start
      when "stop"
        stop
      when "restart"
        stop
        remove_stale_pid_file
        start
      when "status"
        status
      end
    end

    def stop
      if verify_pid_file!
        if running?
          if @config[:tail]
            t = tail_log(0, false)
          end

          warn "Sending QUIT to #{pid}, #{@kill_timeout} timeout"
          Palmade::PuppetMaster::Utils.pidf_kill(@pid_file, @kill_timeout)

          if @config[:tail]
            sleep(2)
            t.exit
          end
        else
          abort "aborted, not running"
        end
      end
    end

    def status
      if verify_pid_file!
        if running?
          warn "#{$0} is running with pid #{pid}"
        else
          warn "#{$0} is not running"
          remove_stale_pid_file
        end
      end
    end

    def start
      @config[:daemonize] = true if @config[:daemonize].nil?

      # let's lock in our pid file
      # and also check if another one like us exists, already!
      if @config[:daemonize]
        remove_stale_pid_file
        daemonize

        write_pid_file
        at_exit do
          remove_pid_file(false) if pid == $$ rescue nil
        end
      end

      # let's run the pre-start code!
      unless @config[:pre_start].nil?
        case @config[:pre_start]
        when String
          require @config[:pre_start]
        when Proc
          @config[:pre_start].call
        else
          raise ArgumentError, "Unsupported :pre_start option, got: #{@config[:pre_start].class}"
        end
      end

      # let's create our logger, if any
      if Palmade::PuppetMaster.logger.nil?
        Palmade::PuppetMaster.logger = @logger
      end

      # let's run our master process
      master_options = Palmade::PuppetMaster::Utils.symbolize_keys(@config[:master_options])
      unless @config[:timeout].nil?
        master_options[:timeout] = @config[:timeout]
      end

      unless @config[:listen].nil?
        master_options[:listen] = @config[:listen]
      end

      master_options[:proc_name] = @proc_name
      master_options[:proc_argv] = @proc_argv

      Palmade::PuppetMaster.run!(master_options) do |m|
        @configurator = nil

        # configurator is a file name
        case @config[:configurator]
        when String
          @configurator = Palmade::PuppetMaster::Configurator.configure(@config[:configurator], m, @config, self)
        end

        if !@config[:block].nil?
          @config[:block].call(m, @configurator, @config, self)
        elsif !@configurator.nil?
          @configurator.call(:main)
        end
      end
    rescue PidFileExist => e
      warn e.message
    end

    protected

    def verify_pid_file!
      unless @pid_file
        warn "Checking pid_file, but i couldn't figure out where the pid file is."
        nil
      else
        @pid_file
      end
    end

    def daemonize
      # let's disable any output, if we're daemonizing
      # and no log file is specified!
      if @config[:log_file].nil?
        warn "We are daemonizing... but no log file is specified, redirecting all output to /dev/null."
        @config[:log_file] = '/dev/null'
      end
      if @config[:log_file] =~ /^syslog:/
        @logger = Syslogger.new
      else
        @logger = Logger.new(@config[:log_file])
      end

      # double fork here, for some reason Daemonize also said
      # we should do it! so i'm doing it.
      exit(0) if fork

      # second fork to get off any remaining terminal
      sess_id = Process.setsid
      exit(0) if fork

      $stdin.reopen("/dev/null")
      $stdin.sync = true

      # let's just re-open the logger file
      @logger.close

      if @config[:log_file] =~ /^syslog:/
        log_type, app_name = @config[:log_file].split(':', 2)
        @logger = Syslogger.new(app_name, Syslog::LOG_PID | Syslog::LOG_CONS, Syslog::LOG_LOCAL0)
        $stdout = $stderr = SysloggerIO.new(@logger)
      else
        @logger = Logger.new(@config[:log_file])
        Palmade::PuppetMaster::Utils.redirect_io($stderr, @config[:log_file])
        Palmade::PuppetMaster::Utils.redirect_io($stdout, @config[:log_file])
        $stdout.sync = $stderr.sync = true
      end
    end

    def tail_log(backtrack = 0, join = true)
      unless @config[:log_file] == '/dev/null'
        tail_signals = [ 'INT', 'TERM', 'KILL', 'QUIT' ]
        t = Thread.new do
          tail_signals.each { |s| trap(s) { Thread.exit } }
          begin
            File.tail(@config[:log_file], backtrack, false)
          ensure
            tail_signals.each { |s| trap(s, 'DEFAULT') }
          end
        end

        join ? t.join : t
      end
    end

    def pid
      Palmade::PuppetMaster::Utils.pidf_read(@pid_file) if verify_pid_file!
    end

    def running?
      Palmade::PuppetMaster::Utils.pidf_running?(@pid_file) if verify_pid_file!
    end

    def remove_pid_file(noisy = true)
      if verify_pid_file! && File.exists?(@pid_file)
        warn ">> Removing PID file #{@pid_file}" rescue nil
        File.delete(@pid_file)
      end
    rescue Exception
      raise if noisy
    end

    def write_pid_file
      if verify_pid_file!
        warn ">> Writing PID to #{@pid_file}"

        FileUtils.mkdir_p File.dirname(@pid_file)
        File.open(@pid_file,"w") { |f| f.write(Process.pid) }
        File.chmod(0644, @pid_file)
      end
    end

    # If PID file is stale, remove it.
    def remove_stale_pid_file
      if verify_pid_file!
        if File.exist?(@pid_file)
          if running?
            raise PidFileExist, "#{@pid_file} already exists, seems like it's already running (process ID: #{pid}). " +
              "Stop the process or delete #{@pid_file}."
          else
            warn ">> Deleting stale PID file #{@pid_file}"
            remove_pid_file
          end
        end
      end
    end
  end
end
