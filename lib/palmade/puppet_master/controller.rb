module Palmade::PuppetMaster
  class Controller
    attr_reader :reexec_pid
    attr_writer :runner

    def initialize(proc_name, proc_argv, command, arguments, config)
      @proc_name = proc_name
      @proc_argv = proc_argv

      @command   = command
      @arguments = arguments
      @config    = config

      @logger   = Logger.new($stderr)
      @pid_file = PidFile.new(@config[:pid_file])

      @kill_timeout = 60
      @reexec_pid   = nil
    end

    def doit!
      case @command
      when "start"
        start
      when "stop"
        stop
      when "restart"
        restart
      when "status"
        status
      when "stats"
        stats
      end
    end

    def stop
      running_or_abort do
        warn "Sending QUIT to #{@pid_file.pid}, #{@kill_timeout} timeout"
        @pid_file.terminate(@kill_timeout)
      end
    end

    def status
      running_or_abort do
        warn "#{$0} is running with pid #{@pid_file.pid}"
      end
    end

    def stats
      running_or_abort do
        print_stats_from_control_port
      end
    end

    def restart
      running_or_abort do
        warn "Sending USR1 to #{@pid_file.pid}"
        @pid_file.kill(:USR1)
      end
    end

    def start
      abort "already running as #{@pid_file.pid}" if @pid_file.running?

      @config[:daemonize] = true if @config[:daemonize].nil?

      create_required_directories

      if @config[:daemonize]
        daemonize

        @pid_file.write
      end

      run_pre_start

      Palmade::PuppetMaster.logger ||= @logger

      master_options = Palmade::PuppetMaster::Utils.symbolize_keys(@config[:master_options])

      # pass non nil config options to master
      [:timeout, :listen, :control_port].each do |key|
        next if @config[key].nil?

        master_options[key] = @config[key]
      end

      master_options[:proc_name] = @proc_name
      master_options[:proc_argv] = @proc_argv
      master_options[:epoll]     = @config[:epoll]

      # let's run our master process
      Palmade::PuppetMaster.run!(master_options,
                                 &method(:initialize_master))
    end

    def run_pre_start
      return if @config[:pre_start].nil?

      case @config[:pre_start]
      when String
        require @config[:pre_start]
      when Proc
        @config[:pre_start].call
      else
        raise ArgumentError, "Unsupported :pre_start option, got: #{@config[:pre_start].class}"
      end
    end

    def restore_pid_file(wpid, status)
      return unless wpid == @reexec_pid

      @logger.error "reexec-ed() master died"
      @reexec_pid = nil
    end

    def kill_and_replace_old_master
      begin
        # the rexec'ed master's pid file basename is just the configured
        # pid_file filename prefixed with ".reexec"
        configured_pid_file_path = @pid_file.path.sub(/\.reexec\.pid$/, '.pid')

        old_pid_file = PidFile.new(configured_pid_file_path)
        @logger.warn "killing old master: #{old_pid_file.pid}"
        old_pid_file.terminate(@kill_timeout)

        @logger.warn "moving pid file to #{configured_pid_file_path}"
        @pid_file.path = configured_pid_file_path
      rescue Errno::ESRCH
        @logger.warn "old master not found."
      end
    end

    def reexec(commit_matricide = false, listeners = {})
      return if @runner.nil? or @runner.start_ctx.nil? or @runner.start_ctx.empty?

      if @reexec_pid
        @logger.warn "Already running a reexec-ed master: #{@reexec_pid}"
        return
      end

      # clear env in advance
      ENV['PUPPET_MASTER_COMMIT_MATRICIDE'] = nil

      @reexec_pid = Kernel.fork do
        listener_fds = ''

        listeners.each do |lk, sockets|
          sockets.each do |sock|
            # IO#close_on_exec= will be available on any future version of
            # Ruby that sets FD_CLOEXEC by default on new file descriptors
            # ref: http://redmine.ruby-lang.org/issues/5041
            sock.close_on_exec = false if sock.respond_to?(:close_on_exec=)
            listener_fds << "#{lk}|#{sock.fileno},"
          end
        end

        ENV['PUPPET_MASTER_FD'] = listener_fds
        ENV['PUPPET_MASTER_COMMIT_MATRICIDE'] = commit_matricide.to_s

        # prefix pid_file basename with ".reexec"
        reexec_pid_file_path = @pid_file.path.sub(/\.pid$/, '.reexec.pid')

        Dir.chdir(@runner.start_ctx[:cwd])
        cmd = [@runner.start_ctx[0]].concat(@runner.start_ctx[:argv] +
                                              ["-P", reexec_pid_file_path])

        @logger.info "executing #{cmd.inspect} (in #{Dir.pwd})"
        exec(*cmd)
      end
    end

    protected
    def print_stats_from_control_port
      UNIXSocket.open(@config[:control_port]) do |c|
        c.write "!stats\n"
        c.write "!quit\n"
        puts $_ while c.gets
      end
    end

    def reexeced?
      ENV['PUPPET_MASTER_FD']? true : false
    end

    def daemonize
      # let's disable any output, if we're daemonizing
      # and no log file is specified!
      case @config[:log_file]
      when nil
        warn "We are daemonizing... but no log file is specified, redirecting all output to /dev/null."
        @config[:log_file] = '/dev/null'
      when /^syslog:/
        @logger = Syslogger.new
      else
        @logger = Logger.new(@config[:log_file])
      end

      unless reexeced?
        exit(0) if fork
        sess_id = Process.setsid
        exit(0) if fork
      end

      $stdin.reopen("/dev/null")
      $stdin.sync = true

      # let's just re-open the logger file
      @logger.close

      if @config[:log_file] =~ /^syslog:/
        log_type, app_name = @config[:log_file].split(':', 2)
        @logger = Syslogger.new(app_name, Syslog::LOG_PID | Syslog::LOG_CONS, Syslog::LOG_LOCAL0)
        Palmade::PuppetMaster::Utils.redirect_io($stderr, '/dev/null')
        Palmade::PuppetMaster::Utils.redirect_io($stdout, '/dev/null')
        $stdout = $stderr = SysloggerIO.new(@logger)
      else
        @logger = Logger.new(@config[:log_file])
        Palmade::PuppetMaster::Utils.redirect_io($stderr, @config[:log_file])
        Palmade::PuppetMaster::Utils.redirect_io($stdout, @config[:log_file])
        $stdout.sync = $stderr.sync = true
      end
    end

    private

    def create_required_directories
      FileUtils.mkdir_p File.dirname(@config[:control_port])
    end

    def running_or_abort(&block)
      if @pid_file.running?
        block.call
      else
        abort "aborted, not running"
      end
    end

    def initialize_master(master)
      master.controller = self
      master.on_callback(:on_reap_dead_children, &method(:restore_pid_file))

      if ENV['PUPPET_MASTER_COMMIT_MATRICIDE']
        master.on_callback_once(:on_all_workers_checked_in, &method(:kill_and_replace_old_master))
      end

      configurator =
        case @config[:configurator]
        when String
          Palmade::PuppetMaster::Configurator.configure(@config[:configurator], master, @config, self)
        else
          nil
        end

      if @config[:block].respond_to?(:call)
        @config[:block].call(master, configurator, @config, self)
      elsif configurator.respond_to?(:call)
        configurator.call(:main)
      end
    end
  end

  class PidFile
    attr_reader :path

    def initialize(path)
      @path = path
    end

    def path=(dest)
      File.rename(path, dest)
      @path = dest
    end

    def pid
      @pid ||= File.read(@path).to_i
    rescue ENOENT
      abort "no pid file"
    end

    def running?
      return false unless exists?
      Process.getpgid(pid) != -1
    rescue Errno::ESRCH
      false
    end

    def write
      remove_stale

      warn "Writing pid to #{@path}"
      FileUtils.mkdir_p File.dirname(path)
      File.open(@path,"w") { |f| f.write(Process.pid) }
      File.chmod(0644, @path)

      at_exit do
        cleanup if pid == $$ rescue nil
      end
    end

    def kill(signal)
      exists? and Process.kill(signal, pid)
    end

    def cleanup
      return unless exists?

      warn "Removing pid file: #{path}"
      File.delete(@path)
    end

    def terminate(timeout = 30)
      signal = timeout == 0 ? :INT : :QUIT

      Process.kill(signal, pid)

      Timeout.timeout(timeout) do
        sleep 0.1 while running?
      end
    rescue Timeout::Error
      warn "Timeout reached. Sending KILL."
      Process.kill(:KILL, pid)
    end

    def exists?
      File.exist?(@path)
    end

    def stale?
      exists? and running?
    end

    private
    def remove_stale
      return unless stale?

      warn "Deleting stale pid file: #{@path}"
      File.delete(@path)
    end
  end
end
