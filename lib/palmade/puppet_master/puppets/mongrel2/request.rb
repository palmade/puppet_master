module Palmade::PuppetMaster
  module Puppets::Mongrel2
    class Request

      attr_reader :headers, :body, :uuid, :conn_id, :path

      # CGI-like request environment variables
      attr_reader :env

      INITIAL_BODY = ''
      # Force external_encoding of request's body to ASCII_8BIT
      INITIAL_BODY.encode!(Encoding::ASCII_8BIT) if INITIAL_BODY.respond_to?(:encode!)

      class << self
        def parse(msg)
          uuid, conn_id, path, rest = msg.split(' ', 4)
          headers, rest = parse_netstring(rest)
          body, _ = parse_netstring(rest)
          headers = Yajl::Parser.parse(headers)
          new(uuid, conn_id, path, headers, body)
        end

        def parse_netstring(ns)
          len, rest = ns.split(':', 2)
          len = len.to_i
          raise "Netstring did not end in ','" unless rest[len].chr == ','
          [rest[0, len], rest[(len + 1)..-1]]
        end
      end

      def initialize(uuid, conn_id, path, headers, body)
        @uuid, @conn_id, @path, @headers, @body = uuid, conn_id, path, headers, StringIO.new(INITIAL_BODY.dup) << body
        @data = headers['METHOD'] == 'JSON' ? Yajl::Parser.parse(body) : {}
        initialize_env
      end

      def initialize_env
        script_name = ENV['RACK_RELATIVE_URL_ROOT'] ||
          (headers['PATTERN'].split('(', 2).first.gsub(/\/$/, '') if headers['PATTERN'])

        @env = {
          'rack.version'      => Rack::VERSION,
          'rack.url_scheme'   => 'http',
          'rack.input'        => @body,
          'rack.errors'       => $stderr,
          'rack.multithread'  => true,
          'rack.multiprocess' => true,
          'rack.run_once'     => false,
          'mongrel2.pattern'  => headers['PATTERN'],
          'GATEWAY_INTERFACE' => 'CGI/1.1',
          'PATH_INFO'         => (headers['PATH'].gsub(script_name, '') if headers['PATH']),
          'QUERY_STRING'      => headers['QUERY'] || '',
          'REQUEST_METHOD'    => headers['METHOD'],
          'REQUEST_PATH'      => headers['PATH'],
          'REQUEST_URI'       => headers['URI'],
          'SCRIPT_NAME'       => script_name,
          'SERVER_PROTOCOL'   => headers['VERSION']
        }

        @env['SERVER_NAME'], @env['SERVER_PORT'] = headers['host'].split(':', 2) if headers['host']
        @env['SERVER_PORT'] ||= '80'
        @env['FRAGMENT'] = headers['FRAGMENT'] if headers['FRAGMENT']

        headers.each do |key, val|
          key = key.upcase.gsub('-', '_')

          unless key =~ /content_(type|length)/i
            key = "HTTP_#{key}"
          end
          @env[key] = val
        end
      end

      def async_callback=(callback)
        @env['async.callback'] = callback
        @env['async.close'] = EventMachine::DefaultDeferrable.new
      end

      def async_close
        @async_close ||= @env[ASYNC_CLOSE]
      end

      def disconnect?
        headers['METHOD'] == 'JSON' && @data['type'] == 'disconnect'
      end

      def close?
        headers['connection'] == 'close' || headers['VERSION'] == 'HTTP/1.0'
      end

    end
  end
end
