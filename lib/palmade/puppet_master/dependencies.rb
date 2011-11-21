module Palmade::PuppetMaster
  module Dependencies
    class << self
      def require_rack
        unless defined?(::Rack)
          gem 'rack', '>= 1.1.0'
          require 'rack'
        end
      end

      def require_thin
        require_rack

        unless defined?(::Thin)
          gem 'thin', '>= 1.2.7'
          require 'thin'
        end
      end

      def require_redis
        unless defined?(::Redis)
          gem 'redis', '>= 2.0.0'
          require 'redis'
        end
      end

      def require_zeromq
        unless defined?(::EM::ZeroMQ)
          require 'em-zeromq'
        end
      end

      def require_yajl
        unless defined?(::Yajl)
            require 'yajl'
        end
      end
    end
  end
end
