module Palmade::PuppetMaster
  module Puppets
    class Mongrel2Puppet < Base
      include Palmade::PuppetMaster::Mixins::FrameworkAdapters

      def initialize(master = nil, family = nil, options = { }, &block)
        super(master, family, options, &block)

        @options[:idle_time] ||= @master.timeout * 0.8
        @adapter               = @options[:adapter]
        @adapter_options       = @options[:adapter_options]
      end

      def build!
        super

        Palmade::PuppetMaster::Dependencies.require_yajl
        Palmade::PuppetMaster::Dependencies.require_rack
        Palmade::PuppetMaster::Dependencies.require_zeromq
      end

      def work_loop(worker, ret = nil, &block)
        master_logger.warn "mongrel2 worker #{worker.proc_tag} started: #{$$}"

        [ :INT ].each { |sig| trap(sig) { } } # do nothing
        [ :QUIT ].each { |sig| trap(sig) { stop_work_loop(worker) } } # graceful shutdown
        [ :TERM, :KILL ].each { |sig| trap(sig) { exit!(0) } } # instant #shutdown

        @backend = Mongrel2::Backend.new(rack_application, @adapter_options[:mongrel2])

        EventMachine.epoll
        EventMachine.kqueue

        EventMachine.run do
          @backend.start

          @idle_timer = EventMachine.add_timer(@options[:idle_time]) { idle_time(worker) }
        end
        worker.stop!

        master_logger.warn "mongrel2 worker #{worker.proc_tag} stopped: #{$$}"

        ret
      end

      def stop_work_loop(worker)
        EM.next_tick do
          @backend.stop
          worker.stop!
          EventMachine.stop
        end
      end

      protected

      def rack_application
        app = load_adapter

        master.revert_logger

        unless @options[:rack_builder].nil?
          app = @options[:rack_builder].call(app, self)
        end

        # If a prefix is required, wrap in Rack URL mapper
        app = Rack::URLMap.new(@options[:prefix] => app) if @options[:prefix]

        # If a stats URL is specified, wrap in Stats adapter
        app = Stats::Adapter.new(app, @options[:stats]) if @options[:stats]

        app
      end

      def idle_time(w)
        if !w.ok? and EM.reactor_running?
          stop_work_loop(w)
        else
          @idle_timer = nil
          notify_alive!(w)

          @idle_timer = EventMachine.add_timer(@options[:idle_time]) { idle_time(w) }
        end
      end

      def notify_alive!(w)
        w.alive! if w.ok?
      end
    end
  end
end
