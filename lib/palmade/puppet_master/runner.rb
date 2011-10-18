module Palmade::PuppetMaster
  class Runner
    $safe_program_name = File.basename($0).gsub('/', '-')

    attr_reader :argv
    attr_reader :config

    DEFAULT_OPTIONS = {
      :listen => [ ],
      :debug => false,
      :pid_file => "tmp/pids/#{$safe_program_name}.pid".freeze,
      :log_file => "log/#{$safe_program_name}.log".freeze,
      :timeout => 30,
      :daemonize => nil,
      :master_options => { },
      :tail => true,
      :configurator => nil,
      :epoll => false
    }

    DEFAULT_CONFIG_FILE = "config/puppet_master.yml".freeze
    DEFAULT_CONFIGURATOR_FILE = "config/puppet_master.rb".freeze

    # commands:
    # - - if no command is specified, it means, start un-daemonized
    # start - starts the master service
    # stop - stops the master
    # restart - stops, then restart (TODO: add binary-replace unicorn/nginx style)
    # hold - kills all main workers
    # resume - restarts all main workers
    # reload - hold, then resume (waiting for all to stop, before resuming)
    # incr - add one more main worker
    # decr - remove one less main worker
    # status - check if the status of the main master
    # replace - replace running with a new instance
    COMMANDS = %w{ start stop restart status hold resume reload incr decr replace }.freeze

    def self.default_config_file; DEFAULT_CONFIG_FILE; end
    def self.default_configurator_file; DEFAULT_CONFIGURATOR_FILE; end

    def self.commands; COMMANDS; end

    def initialize(argv, options = { }, &block)
      # the following lines where copied from unicorn
      # i'm too lame to figure out what they're for!
      $stdin.sync = $stdout.sync = $stderr.sync = true
      $stdin.binmode; $stdout.binmode; $stderr.binmode

      @argv = argv.clone
      @argv.delete_if { |a| a.strip.empty? }

      @argv_options = Palmade::PuppetMaster::Config.new

      @config = Palmade::PuppetMaster::Config.new
      @config.update!(DEFAULT_OPTIONS)
      @config.update!(options)
      @config[:block] = block if block_given?

      @command = nil
      @arguments = [ ]
    end

    #
    # for main workers only:
    # hold - kills all workers
    # resume - resumes all workers
    #
    # options:
    # -C - specify config files
    # -c - change dir, before start
    # -s - number of main workers to run
    # -e - environment to use (app specific)
    # -l - listen to a specific port (can be multiple)
    # -P - where to store pid file, defaults to: "#{cur_dir}/tmp/pids"
    # -L - where to store log files, defaults to: "#{cur_dir}/log"
    # -u - user to run master daemon on
    # -g - group to run master daemon on
    # --tag - additional text, to add right after proc_name
    # -t - default worker timeout, defaults to: 30s
    #
    # note: -l should support unix domain sockets
    # format: -l "host:port" -l "/path/socket" -l "key:host:port" -l "key:/path/socket"
    # key - is used to identify listening ports, and can be used by child workers to use
    # unnamed keys typically belongs to main worker
    def argv_parser
      if defined?(@parser)
        @parser
      else
        @parser = OptionParser.new do |opts|
          opts.banner = "Usage: #{File.basename($0)} [options] #{self.class.commands.join(' | ')}"
          opts.version = "0.1"

          opts.separator ""
          opts.separator "Config options:"

          opts.on("-c", "--chdir :chdir",
                  "Change to working directory before doing anything!") { |d| @argv_options[:chdir] = d }
          opts.on("-C", "--config :config",
                  "Specify a config file to read from (yml format)") { |c| @argv_options[:config] = c }

          opts.separator ""
          opts.separator "Server options:"

          opts.on("-l", "--listen :listen",
                  "Listen on a port TCP or Socket " +
                  "e.g. 80, 127.0.0.1:80, /pathto/socket, key:127.0.0.1:80"
                  ) { |l| @argv_options[:listen] ||= [ ]; @argv_options[:listen].push(l) }
          opts.on("-s", "--servers :servers",
                  "Number of main workers to run"
                  ) { |s| @argv_options[:servers] = s.to_i }
          opts.on("-t", "--timeout :timeout",
                  "Timeout limit (in secs) for workers before being killed"
                  ) { |t| @argv_options[:timeout] = t.to_i }

          opts.separator ""
          opts.separator "Application options:"

          opts.on("-e", "--environment :environment",
                  "Sets the application environment (app specific)"
                  ) { |e| @argv_options[:environment] = e }

          opts.on("-r", "--configurator :configurator",
                  "Sets the configurator file (app specific)"
                  ) { |e| @argv_options[:configurator] = e }

          opts.on("-o", "--options :options",
                  "Specify a file with (app specific)"
                  ) { |o| @argv_options[:options] = o }
          opts.on("--prefix PATH",
                  "Mount the app under PATH (start with /)"
                  ) { |path| @argv_options[:prefix] = path }

          opts.separator ""
          opts.separator "Daemon options:"

          opts.on("--tag :tag",
                  "Additional tag name to attach to master and workers"
                  ) { |t| @argv_options[:tag] = t }
          opts.on("-P :pid_file", "--pid",
                  "Where to store pid file"
                  ) { |p| @argv_options[:pid_file] = p }
          opts.on("-L", "--log :log_file",
                  "Where to store log file"
                  ) { |l| @argv_options[:log_file] = l }
          opts.on("-u", "--user :user",
                  "Run daemon as this user"
                  ) { |u| @argv_options[:user] = u }
          opts.on("-g", "--group :group",
                  "Run daemon as this group"
                  ) { |g| @argv_options[:group] = g }
          opts.on("-q", "--quiet",
                  "Quiet invocation, no tailing, etc."
                  ) { |q| @argv_options[:tail] = false }

          opts.separator ""
          opts.separator "Common options:"

          opts.on_tail("-h", "--help", "Show this message") { puts opts; exit }
          opts.on_tail('-v', '--version', "Show version")
        end
      end
    end

    # precedence:
    # - defaults
    # - options passed to runner!
    # - config file, if specified or probed
    # - command line options
    def parse!
      # let's parse!
      argv_parser.parse!(@argv)
      @command = @argv.first
      @arguments = @argv[1..-1]
    end

    def run
      cur_dir = Dir.pwd
      parse!

      pn = File.basename($0)

      # let's find the config file
      if @argv_options[:config].nil?
        app_config = File.join("config/#{pn}.yml")
        if File.exists?(app_config)
          @config[:config] = app_config
        elsif File.exists?(self.class.default_config_file)
          @config[:config] = self.class.default_config_file
        end
      else
        @config[:config] = @argv_options[:config]
      end
      @config.load_from_yaml(@config[:config]) unless @config[:config].nil?

      # let's merge the command line arguments now to our global config
      @config.update!(@argv_options)

      # let's move to chdir right now, so we can load any relative config files properly
      Dir.chdir(@config[:chdir]) unless @config[:chdir].nil?

      # let's find the configurator file
      if @config[:configurator].nil?
        app_configurator = File.join("config/#{pn}.rb")
        if File.exists?(app_configurator)
          @config[:configurator] = app_configurator
        elsif File.exists?(self.class.default_configurator_file)
          @config[:configurator] = self.class.default_configurator_file
        end
      end

      # if no command is specified, by default, start but no daemonized
      # useful when debugging
      if @command.nil?
        @command = 'start'
        @config[:daemonize] = false
      end

      if self.class.commands.include?(@command)
        Palmade::PuppetMaster::Controller.new(pn, @argv, @command, @arguments, @config)
      else
        abort "Unknown command: #{@command}. Use one of #{self.class.commands.join(', ')}"
      end
    ensure
      Dir.chdir(cur_dir)
    end
  end
end
