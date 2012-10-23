module Palmade::PuppetMaster
  module Puppets::Mongrel2
    class Connection

      CONTENT_LENGTH    = 'Content-Length'.freeze
      TRANSFER_ENCODING = 'Transfer-Encoding'.freeze
      CHUNKED_REGEXP    = /\bchunked\b/i.freeze

      AsyncResponse = [-1, {}, []].freeze

      def initialize(app, response_sock, chroot)
        @app           = app
        @response_sock = response_sock
        @chroot        = chroot
      end

      def on_readable(socket, messages)
        messages.each do |msg|
          @request = msg.nil? ? nil : Request.parse(msg.copy_out_string, @chroot)
          next if @request.nil? || @request.disconnect?
          process
        end
      end

      def process
        post_process(pre_process)
      end

      def pre_process
        @request.async_callback = method(:post_process)

        response = AsyncResponse

        # ignore connection if mongrel2 is starting an upload
        # we'll process this once uploading is already done.
        return if @request.upload_starting?

        @request.verify_upload if @request.upload_done?

        catch(:async) do
          response = @app.call(@request.env)
        end

        response
      end

      def post_process(result)
        return unless result

        # Status code -1 indicates that we're going to respond later (async).
        return if result.first == AsyncResponse.first

        # Set the Content-Length header if possible
        set_content_length(result) if need_content_length?(result)

        status, headers, body = result
        reply(body, status, headers)
      end

      def reply(body, status = 200, headers = {})
        resp = Response.new(@response_sock)
        resp.send_http(@request, body, status, headers)
        resp.close(@request) if @request.close?
      end

      protected

      def need_content_length?(result)
        status, headers, body = result
        return false if status == -1
        return false if headers.has_key?(CONTENT_LENGTH)
        return false if (100..199).include?(status) || status == 204 || status == 304
        return false if headers.has_key?(TRANSFER_ENCODING) && headers[TRANSFER_ENCODING] =~ CHUNKED_REGEXP
        return false unless body.kind_of?(String) || body.kind_of?(Array)
        true
      end

      def set_content_length(result)
        headers, body = result[1..2]
        case body
        when String
          # See http://redmine.ruby-lang.org/issues/show/203
          headers[CONTENT_LENGTH] = (body.respond_to?(:bytesize) ? body.bytesize : body.size).to_s
        when Array
          bytes = 0
          body.each do |p|
            bytes += p.respond_to?(:bytesize) ? p.bytesize : p.size
          end
          headers[CONTENT_LENGTH] = bytes.to_s
        end
      end

    end
  end
end
