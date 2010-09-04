module Palmade::PuppetMaster
  class ThinPuppet < Palmade::PuppetMaster::Puppet
    DEFAULT_OPTIONS = {
      :adapter => nil,
      :adapter_options => { },
      :listen_key => nil,
      :idle_time => 15,
      :post_process => nil,
      :idle_process => nil,
      :prefix => nil,
      :stats => nil,
      :max_total_connections => 10000,
      :max_current_connections => 100,
      :max_persistent_connections => 50,
      :rack_builder => nil,
      :threaded => false,
      :thin_configurator => nil
    }

    attr_accessor :thin
    def backend; thin.backend; end

    attr_reader :total_connections
    attr_accessor :max_total_connections
    attr_accessor :max_current_connections

    def initialize(options = { }, &block)
      super(DEFAULT_OPTIONS.merge(options), &block)

      @thin = nil

      if @proc_tag.nil?
        @proc_tag = "thin"
      else
        @proc_tag = "#{@proc_tag}.thin"
      end

      @listen_key = @options[:listen_key]
      @adapter = @options[:adapter]
      @adapter_options = @options[:adapter_options]

      @post_process = @options[:post_process]
      @idle_process = @options[:idle_process]
      @idle_timer = nil

      @total_connections = 0
      @max_total_connections = @options[:max_total_connections]

      # how many connections should be outstanding (including
      # persistent ones)
      @max_current_connections = @options[:max_current_connections]
      @max_persistent_connections = @options[:max_persistent_connections]
    end

    def build!(m, fam)
      super(m, fam)

      Palmade::PuppetMaster.require_thin
      boot_thin!
    end

    def after_fork(w)
      super(w)
      master = w.master

      # let's set the sockets with the proper settings for
      # attaching as acceptors to EventMachine
      if master.listeners[@listen_key].nil? || master.listeners[@listen_key].empty?
        raise ArgumentError, "No configured #{@listen_key || 'default'} listeners from master"
      else
        sockets = master.listeners[@listen_key]
      end

      # * FD_CLOEXEC <-- this is done on the worker class (init method)
      # * SO_REUSEADDR <-- TODO: figure out why we need this? couldn't find it in unicorn
      # * Set non-blocking <--
      sockets.each do |s|
        s.fcntl(Fcntl::F_SETFL, Fcntl::O_NONBLOCK)
      end

      # let's add reference to ourselves, for the post_process callback below
      @thin.backend.worker = w
      @thin.backend.max_current_connections = @max_current_connections

      # attach sockets
      @thin.backend.sockets = sockets

      # configure backend
      @thin.backend.config
    end

    def work_loop(worker, ret = nil, &block)
      loop_start = Time.now
      master_logger.warn("thin worker #{worker.proc_tag} started: #{$$}, " +
                         "stats: #{@max_total_connections} #{@max_current_connections} #{@max_persistent_connections} (#{loop_start})")

      # trap(:USR1) {  } do nothing, it should reload logs
      [ :INT ].each { |sig| trap(sig) { } } # do nothing
      [ :QUIT ].each { |sig| trap(sig)  { stop_work_loop(worker) } } # graceful shutdown
      [ :TERM, :KILL ].each { |sig| trap(sig) { stop_work_loop(worker, true) } } # instant shutdown

      EventMachine.run do
        EventMachine.epoll rescue nil
        EventMachine.kqueue rescue nil

        # do some work
        if block_given?
          yield(self, worker)
        elsif !@work_loop.nil?
          @work_loop.call(self, worker)
        else
          start!
        end

        # schedule a timer, so we can check-in every request
        # just set it to 5 secs, so not to unnecessarily busy ourselves
        @idle_timer = EventMachine.add_timer(@options[:idle_time]) { idle_time(worker) }
      end
      worker.stop!

      master_logger.warn("thin worker #{worker.proc_tag} stopped: #{$$}, " +
                         "stats: #{@total_connections}, started #{(Time.now - loop_start).to_i} sec(s) ago (#{loop_start})")

      ret
    end

    def stop_work_loop(worker, now = false)
      unless @idle_timer.nil?
        EventMachine.cancel_timer(@idle_timer)
        @idle_timer = nil
      end

      if now
        @thin.backend.stop!
      else
        @thin.backend.stop
      end

      worker.stop!
    end

    def start!
      if @thin.nil?
        raise ArgumentError, "Thin not yet booted!"
      else
        @thin.backend.start
      end
    end

    def post_process(conn, w)
      notify_alive!(w) unless w.nil?

      # do something, after every request is done!
      @post_process.call(conn, w) unless @post_process.nil?
    end

    def connection_finished(conn, w)
      @total_connections += 1
      if @max_total_connections.nil? || @total_connections < @max_total_connections
        # let's try sleeping for a short time, to give other
        # nodes a chance to do their work
        # sleep(0.1)
        # master_logger.warn "connection finished"
      else
        # otherwise, we've served our max requests!
        master_logger.warn "thin worker #{w.proc_tag} served max connections #{@max_total_connections}, gracefully signing off"
        stop_work_loop(w)
      end
    end

    protected

    def idle_time(w)
      @idle_timer = nil
      notify_alive!(w)

      # only, if we're not doing anything at all!
      @idle_process.call(w) if !@idle_process.nil? && @thin.backend.empty?

      @idle_timer = EventMachine.add_timer(@options[:idle_time]) { idle_time(w) }
    end

    def notify_alive!(w)
      w.alive! if w.ok?
    end

    def boot_thin!
      thin_opts = { }

      # we use our own acceptor based backend
      thin_opts[:backend] = Palmade::PuppetMaster::ThinBackend

      # disable signals, since we're doing this ourselves
      thin_opts[:signals] = false

      @thin = Thin::Server.new(thin_opts)
      @thin.backend.puppet = self

      @thin.threaded = @options[:threaded]
      if @thin.threaded?
        EventMachine.threadpool_size = @options[:max_current_connections] + 2
        master_logger.info "Using multithreaded thin and eventmachine support"
      end

      @thin.maximum_connections = @max_current_connections
      @thin.maximum_persistent_connections = @max_persistent_connections

      unless @options[:thin_configurator].nil?
        @options[:thin_configurator].call(@thin)
      end

      app = load_adapter

      # added support to hook a Rack builder into the Thin boot-up
      # process. this is commonly used when the app framework don't
      # support rack style middleware attachment (e.g. Rails 2.x ActionController:Dispatcher.middleware)
      unless @options[:rack_builder].nil?
        if app.is_a?(Rack::Adapter::Rails)
          ra = app.send(:instance_variable_get, :@rails_app)
          ra = @options[:rack_builder].call(ra, self)
          app.send(:instance_variable_set, :@rails_app, ra)
        else
          app = @options[:rack_builder].call(app, self)
        end
      end

      @thin.app = app

      # If a prefix is required, wrap in Rack URL mapper
      @thin.app = Rack::URLMap.new(@options[:prefix] => @thin.app) if @options[:prefix]

      # If a stats URL is specified, wrap in Stats adapter
      @thin.app = Stats::Adapter.new(@thin.app, @options[:stats]) if @options[:stats]
    end

    def load_adapter
      unless @adapter.nil?
        ENV['RACK_ENV'] = @adapter_options[:environment] || 'development'
        Object.const_set('RACK_ENV', @adapter_options[:environment] || 'development')

        if @adapter.is_a?(Module)
          @adapter
        elsif @adapter.respond_to?(:call)
          @adapter.call(self)
        elsif @adapter.is_a?(Class)
          @adapter.new(@adapter_options)
        elsif @adapter == :sinatra
          # let's load the sinatra adapter found on config/sinatra.rb
          load_sinatra_adapter
        elsif @adapter == :camping
          # let's load the camping adapter found on config/camping.rb
          load_camping_adapter
        else
          opts = @adapter_options.merge(:prefix => @options[:prefix])
          Rack::Adapter.for(@adapter, opts)
        end
      else
        raise ArgumentError, "Rack adapter for Thin is not specified. I'm too lazy to probe what u want to use."
      end
    end

    def load_camping_adapter
      root = @adapter_options[:root] || Dir.pwd
      camping_boot = File.join(root, "config/camping.rb")
      if File.exists?(camping_boot)

        Object.const_set('CAMPING_ENV', @adapter_options[:environment])
        Object.const_set('CAMPING_ROOT', @adapter_options[:root])
        Object.const_set('CAMPING_PREFIX', @adapter_options[:prefix])
        Object.const_set('CAMPING_OPTIONS', @adapter_options)

        require(camping_boot)

        if defined?(::Camping)
          # by now, camping should have been loaded
          # let's attach the main camping app to thin server
          unless Camping::Apps.first.nil?
            Camping::Apps.first
          else
            raise ArgumentError, "No camping app defined"
          end
        else
          raise LoadError, "It looks like Camping gem is not loaded properly (::Camping not defined)"
        end
      else
        raise ArgumentError, "Set to load camping adapter, but could not find config/camping.rb"
      end
    end

    def load_sinatra_adapter
      root = @adapter_options[:root] || Dir.pwd
      sinatra_boot = File.join(root, "config/sinatra.rb")
      if File.exists?(sinatra_boot)

        Object.const_set('SINATRA_ENV', @adapter_options[:environment])
        Object.const_set('SINATRA_ROOT', @adapter_options[:root])
        Object.const_set('SINATRA_PREFIX', @adapter_options[:prefix])
        Object.const_set('SINATRA_OPTIONS', @adapter_options)

        require(sinatra_boot)

        if defined?(::Sinatra)
          if Object.const_defined?('SINATRA_APP')
            Object.const_get('SINATRA_APP')
          elsif defined?(::Sinatra::Application)
            Sinatra::Application
          else
            raise ArgumentError, "No sinatra app defined"
          end
        else
          raise LoadError, "It looks like Sinatra gem is not loaded properly (::Sinatra not defined)"
        end
      else
        raise ArgumentError, "Set to load sinatra adapter, but could not find config/sinatra.rb"
      end
    end
  end
end
