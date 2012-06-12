module Palmade::PuppetMaster
  module Puppets::Mongrel2
    class Request

      attr_reader :headers, :body, :uuid, :conn_id, :path
      attr_reader :env

      class << self
        def parse(msg)
          uuid, conn_id, path, rest = msg.split(' ', 4)
          json_headers, rest        = parse_netstring(rest)
          body, _                   = parse_netstring(rest)
          headers                   = Yajl::Parser.parse(json_headers)

          new(uuid, conn_id, path, headers, body)
        end

        def parse_netstring(ns)
          len, rest = ns.split(':', 2)
          len       = len.to_i
          raise "Netstring did not end in ','" unless rest[len].chr == ','
          [rest[0, len], rest[(len + 1)..-1]]
        end
      end

      def initialize(uuid, conn_id, path, headers, body)
        @uuid, @conn_id, @path, @headers = uuid, conn_id, path, headers

        @body = StringIO.new(body)
        @body.set_encoding(Encoding::ASCII_8BIT) if @body.respond_to?(:set_encoding)

        @data = headers['METHOD'] == 'JSON' ? Yajl::Parser.parse(body) : {}

        initialize_env
      end

      def initialize_env
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
          'PATH_INFO'         => headers['PATH'],
          'QUERY_STRING'      => headers['QUERY'] || '',
          'REQUEST_METHOD'    => headers['METHOD'],
          'REQUEST_PATH'      => headers['PATH'],
          'REQUEST_URI'       => headers['URI'],
          'SCRIPT_NAME'       => '',
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
