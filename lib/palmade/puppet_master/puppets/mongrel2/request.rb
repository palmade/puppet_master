module Palmade::PuppetMaster
  module Puppets::Mongrel2
    class Request

      attr_reader :headers, :body, :uuid, :conn_id, :path

      # CGI-like request environment variables
      attr_reader :env

      class << self
        def parse(msg)
          # UUID CONN_ID PATH SIZE:HEADERS,SIZE:BODY,
          uuid, conn_id, path, rest = msg.split(' ', 4)
          headers, rest = parse_netstring(rest)
          body, _ = parse_netstring(rest)
          headers = Puppet::JSON.parse(headers)
          new(uuid, conn_id, path, headers, body)
        end

        def parse_netstring(ns)
          # SIZE:HEADERS,

          len, rest = ns.split(':', 2)
          len = len.to_i
          raise "Netstring did not end in ','" unless rest[len].chr == ','
          [rest[0, len], rest[(len + 1)..-1]]
        end
      end

      def initialize(uuid, conn_id, path, headers, body)
        @uuid, @conn_id, @path, @headers, @body = uuid, conn_id, path, headers, body
        @data = headers['METHOD'] == 'JSON' ? Puppet::JSON.parse(body) : {}
        initialize_env
      end

      def initialize_env
        script_name = ENV['RACK_RELATIVE_URL_ROOT'] ||
          (headers['PATTERN'].split('(', 2).first.gsub(/\/$/, '') if headers['PATTERN'])

        @env = {
          'rack.version' => Rack::VERSION,
          'rack.url_scheme' => 'http', # Only HTTP for now
          'rack.input' => StringIO.new(@body),
          'rack.errors' => $stderr,
          'rack.multithread' => true,
          'rack.multiprocess' => true,
          'rack.run_once' => false,
          'mongrel2.pattern' => headers['PATTERN'],
          'REQUEST_METHOD' => headers['METHOD'],
          'SCRIPT_NAME' => script_name,
          'PATH_INFO' => (headers['PATH'].gsub(script_name, '') if headers['PATH']),
          'QUERY_STRING' => headers['QUERY'] || ''
        }

        @env['SERVER_NAME'], @env['SERVER_PORT'] = headers['host'].split(':', 2) if headers['host']
        headers.each do |key, val|
          unless key =~ /content_(type|length)/i
            key = "HTTP_#{key.upcase.gsub('-', '_')}"
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
