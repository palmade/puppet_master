module Palmade::PuppetMaster
  module Mixins
    module FrameworkAdapters
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
          elsif @adapter == :rack_legacy
            load_rack_adapter
          elsif @adapter == :sinatra
            # let's load the sinatra adapter found on config/sinatra.rb
            load_sinatra_adapter
          elsif @adapter == :camping
            # let's load the camping adapter found on config/camping.rb
            load_camping_adapter

          else
            opts = @adapter_options.merge(:prefix => @options[:prefix])

            if defined?(Rack::Adapter) and Rack::Adapter.respond_to?(:for)
              Rack::Adapter.for(@adapter, opts)
            elsif File.exist?('config/environment.rb') # if rails
              require  File.join(PUPPET_MASTER_ROOT_DIR, 'lib', 'ext', 'rack',
                                 'adapter', 'rails') unless defined? Rack::Adapter::Rails
              Rack::Adapter::Rails.new(opts.merge(:root => opts[:chdir]))
            else
              raise ArgumentError, "Adapter not found: #{@adapter}"
            end
          end
        else
          raise ArgumentError, "Rack adapter was not specified. I'm too lazy to probe what u want to use."
        end
      end

      def load_camping_adapter
        root = @adapter_options[:root] || Dir.pwd

        if @adapter_options.include?(:camping_boot)
          camping_boot = File.join(root, @adapter_options[:camping_boot])
        else
          camping_boot = File.join(root, "config/camping.rb")
        end

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
          raise ArgumentError, "Set to load camping adapter, but could not find #{camping_boot}"
        end
      end

      def load_sinatra_adapter
        root = @adapter_options[:root] || Dir.pwd

        if @adapter_options.include?(:sinatra_boot)
          sinatra_boot = @adapter_options[:sinatra_boot]
        else
          sinatra_boot = File.join(root, "config/sinatra.rb")
        end

        Object.const_set('SINATRA_ENV', RACK_ENV)
        Object.const_set('SINATRA_ROOT', @adapter_options[:root])
        Object.const_set('SINATRA_PREFIX', @adapter_options[:prefix])
        Object.const_set('SINATRA_OPTIONS', @adapter_options)

        case sinatra_boot
        when String
          if File.exists?(sinatra_boot)
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
        when Proc
          sinatra_boot.call
        else
          raise ArgumentError, "#{sinatra_boot} not supported"
        end
      end

      def load_rack_adapter
        root = @adapter_options[:root] || Dir.pwd

        if @adapter_options.include?(:rack_boot)
          rack_boot = @adapter_options[:rack_boot]
        else
          rack_boot = File.join(root, "config.ru")
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
end
