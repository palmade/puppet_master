require 'rack'
require 'em-zeromq'

begin
  require 'yajl'
rescue LoadError
  begin
    require 'json'
  rescue LoadError
    raise "You need either the yajl-ruby or json gems present in order to parse JSON!"
  end
end

MONGREL2_PUPPET_LIBS_PATH = File.expand_path(File.join(File.dirname(__FILE__), 'mongrel2_puppet'))

module Palmade::PuppetMaster
  class Mongrel2Puppet < Palmade::PuppetMaster::Puppet

    JSON = Object.const_defined?('Yajl') ? ::Yajl::Parser : ::JSON
    DEFAULT_OPTIONS = Palmade::PuppetMaster::Puppet::DEFAULT_OPTIONS.merge({
      :idle_time => 15,
    })

    autoload :RailsAdapter, File.join(MONGREL2_PUPPET_LIBS_PATH, 'rails_adapter')
    autoload :Backend, File.join(MONGREL2_PUPPET_LIBS_PATH, 'backend')
    autoload :Connection, File.join(MONGREL2_PUPPET_LIBS_PATH, 'connection')
    autoload :Request, File.join(MONGREL2_PUPPET_LIBS_PATH, 'request')
    autoload :Response, File.join(MONGREL2_PUPPET_LIBS_PATH, 'response')

    def initialize(options = { }, &block)
      super(DEFAULT_OPTIONS.merge(options), &block)

      @adapter = @options[:adapter]
      @adapter_options = @options[:adapter_options]
    end

    def work_loop(worker, ret = nil, &block)
      master_logger.warn "mongrel2 worker #{worker.proc_tag} started: #{$$}"

      [ :INT ].each { |sig| trap(sig) { } } # do nothing
      [ :QUIT ].each { |sig| trap(sig) { stop_work_loop(worker) } } # graceful shutdown
      [ :TERM, :KILL ].each { |sig| trap(sig) { exit!(0) } } # instant #shutdown

      @backend = Mongrel2Puppet::Backend.new(rack_application, @adapter_options[:mongrel2])

      EventMachine.run do
        EventMachine.epoll rescue nil
        EventMachine.kqueue rescue nil

        @backend.start

        @idle_timer = EventMachine.add_timer(@options[:idle_time]) { idle_time(worker) }
      end
      worker.stop!

      master_logger.warn "mongrel2 worker #{worker.proc_tag} stopped: #{$$}"

      ret
    end

    def stop_work_loop(worker)
      @backend.stop
      worker.stop!
      EventMachine.stop_event_loop if EventMachine.reactor_running?
    end

    protected

    def rack_application
      app = load_adapter

      # Revert logger if Rails changes Logger behavior
      if master_logger.is_a?(Logger)
        if Logger.private_instance_methods.include?('old_format_message')
          master_logger.instance_eval do
            alias format_message old_format_message
          end
        end
        if defined?(Logger::Formatter)
          master_logger.formatter = Logger::Formatter.new
        end
      end

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
      @idle_timer = nil
      notify_alive!(w)
      @idle_timer = EventMachine.add_timer(@options[:idle_time]) { idle_time(w) }
    end

    def notify_alive!(w)
      w.alive! if w.ok?
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
        elsif @adapter == :rack
          load_rack_adapter
        elsif @adapter == :sinatra
          # let's load the sinatra adapter found on config/sinatra.rb
          load_sinatra_adapter
        elsif @adapter == :camping
          # let's load the camping adapter found on config/camping.rb
          load_camping_adapter
        else
          opts = @adapter_options.merge(:prefix => @options[:prefix])
          RailsAdapter.new(opts.merge(:root => opts[:chdir]))
        end
      else
        raise ArgumentError, "Rack adapter for Mongrel2 is not specified. I'm too lazy to probe what u want to use."
      end
    end

    def load_camping_adapter
      root = @adapter_options[:root] || Dir.pwd
      camping_boot = File.join(root, "config/camping.rb")
      if File.exists?(camping_boot)

        Object.const_set('CAMPING_ENV', RACK_ENV)
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

        Object.const_set('SINATRA_ENV', RACK_ENV)
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

    def load_rack_adapter
      root = @adapter_options[:root] || Dir.pwd

      if @adapter_options.include?(:rack_boot)
        rack_boot = @adapter_options[:rack_boot]
      else
        rack_boot = File.join(root, "config/rack.rb")
        unless File.exists?(rack_boot)
          raise ArgumentError, "Set to load rack adapter, but could not find #{rack_boot}"
        end
      end

      Object.const_set('RACK_ROOT', @adapter_options[:root])
      Object.const_set('RACK_PREFIX', @adapter_options[:prefix])
      Object.const_set('RACK_OPTIONS', @adapter_options)

      rack_app = nil

      case rack_boot
      when String
        require(rack_boot)
      when Proc
        rack_app = rack_boot.call
      else
        raise ArgumentError, "Unsupported rack_boot option, #{rack_boot.class}"
      end

      if !rack_app.nil?
        rack_app
      elsif Object.const_defined?('RACK_APP')
        Object.const_get('RACK_APP')
      else
        raise ArgumentError, "No rack app defined"
      end
    end

  end
end
