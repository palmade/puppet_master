module Palmade::PuppetMaster
  module Mixins
    module RackAddForwardedSupport
      # The following methods were taken from Rack v1.3. They're
      # copied here, for convenience purposes. To use, just call this
      # in your initialization code,
      #
      # Rack::Request.send(:include, Palmade::PuppetMaster::Mixins::RackAddForwardedSupport)
      #
      def port_with_forwarded_support
        if port = host_with_port.split(/:/)[1]
          port.to_i
        elsif port = @env['HTTP_X_FORWARDED_PORT']
          port.to_i
        elsif ssl?
          443
        elsif @env.has_key?("HTTP_X_FORWARDED_HOST")
          80
        else
          @env["SERVER_PORT"].to_i
        end
      end

      def scheme_with_forwarded_support
        if @env['HTTPS'] == 'on'
          'https'
        elsif @env['HTTP_X_FORWARDED_SSL'] == 'on'
          'https'
        elsif @env['HTTP_X_FORWARDED_PROTO']
          @env['HTTP_X_FORWARDED_PROTO'].split(',')[0]
        else
          @env["rack.url_scheme"]
        end
      end

      def self.included(base)
        base.class_eval do
          alias :port_without_forwarded_support :port
          alias :port :port_with_forwarded_support

          alias :scheme_without_forwarded_support :scheme
          alias :scheme :scheme_with_forwarded_support
        end
      end
    end
  end
end
