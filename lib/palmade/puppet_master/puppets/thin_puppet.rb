# -*- encoding: utf-8 -*-

module Palmade::PuppetMaster
  module Puppets
    class ThinPuppet < Base
      include Palmade::PuppetMaster::Mixins::FrameworkAdapters

      DEFAULT_OPTIONS = {
        :adapter => nil,
        :adapter_options => { },
        :listen_key => nil,
        :idle_time => nil,
        :post_process => nil,
        :idle_process => nil,
        :prefix => nil,
        :stats => nil,
        :max_total_connections => 10000,
        :max_current_connections => 100,
        :max_persistent_connections => 50,
        :rack_builder => nil,
        :threaded => false,
        :thin_configurator => nil,
        :logging_debug => false,
        :logging_trace => false
      }

      attr_accessor :thin
      def backend; thin.backend; end

      attr_reader :total_connections
      attr_accessor :max_total_connections
      attr_accessor :max_current_connections

      def initialize(master = nil, family = nil, options = { }, &block)
        super(master, family, DEFAULT_OPTIONS.merge(options), &block)

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

        @options[:idle_time] ||= @master.timeout * 0.8

        @total_connections     = 0
        @max_total_connections = @options[:max_total_connections]

        # how many connections should be outstanding (including
        # persistent ones)
        @max_current_connections = @options[:max_current_connections]
        @max_persistent_connections = @options[:max_persistent_connections]
      end

      def build!
        super

        Palmade::PuppetMaster::Dependencies.require_thin
        boot_thin!
      end

      def after_fork(w)
        super(w)

        # let's set the sockets with the proper settings for
        # attaching as acceptors to EventMachine
        if @master.listeners[@listen_key].nil? || @master.listeners[@listen_key].empty?
          raise ArgumentError, "No configured #{@listen_key || 'default'} listeners from master"
        else
          sockets = @master.listeners[@listen_key]
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

        EventMachine.epoll
        EventMachine.kqueue

        EventMachine.run do
          # do some work
          if block_given?
            yield(self, worker)
          elsif !@work_loop.nil?
            @work_loop.call(self, worker)
          else
            start!
          end

          notify_alive!(worker)

          # schedule a timer, so we can check-in every request
          # just set it to 15 secs, so not to unnecessarily busy ourselves
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

          # master_logger.warn "connection finished #{conn}"
        else
          # otherwise, we've served our max requests!
          master_logger.warn "thin worker #{w.proc_tag} served max connections #{@max_total_connections}, gracefully signing off"
          stop_work_loop(w)
        end
      end

      protected

      def idle_time(w)
        if !w.ok? and EM.reactor_running?
          stop_work_loop(w)
        else
          @idle_timer = nil
          notify_alive!(w)

          @idle_process.call(w) if !@idle_process.nil? && @thin.backend.empty?

          @idle_timer = EventMachine.add_timer(@options[:idle_time]) { idle_time(w) }
        end
      end

      def notify_alive!(w)
        w.alive! if w.ok?
      end

      def boot_thin!
        # let's set thin log debugging and trace
        ::Thin::Logging.debug = @options[:logging_debug]
        ::Thin::Logging.trace = @options[:logging_trace]

        thin_opts = { }

        # we use our own acceptor based backend
        thin_opts[:backend] = Thin::Backend

        # disable signals, since we're doing this ourselves
        thin_opts[:signals] = false

        @thin = ::Thin::Server.new(thin_opts)
        @thin.backend.puppet = self

        @thin.threaded = @options[:threaded]
        if @thin.threaded?
          EventMachine.threadpool_size = @options[:max_current_connections] + 2
          master_logger.info "Using multithreaded thin and eventmachine support"
        end

        @thin.maximum_persistent_connections = @max_persistent_connections

        unless @options[:thin_configurator].nil?
          @options[:thin_configurator].call(@thin)
        end

        app = load_adapter

        master.revert_logger

        unless @options[:rack_builder].nil?
          app = @options[:rack_builder].call(app, self)
        end

        @thin.app = app

        # If a prefix is required, wrap in Rack URL mapper
        @thin.app = Rack::URLMap.new(@options[:prefix] => @thin.app) if @options[:prefix]

        # If a stats URL is specified, wrap in Stats adapter
        @thin.app = Stats::Adapter.new(@thin.app, @options[:stats]) if @options[:stats]
      end
    end
  end
end
