module Palmade::PuppetMaster
  class Mongrel2Puppet::Response

    StatusMessage = {
      100 => 'Continue',
      101 => 'Switching Protocols',
      200 => 'OK',
      201 => 'Created',
      202 => 'Accepted',
      203 => 'Non-Authoritative Information',
      204 => 'No Content',
      205 => 'Reset Content',
      206 => 'Partial Content',
      300 => 'Multiple Choices',
      301 => 'Moved Permanently',
      302 => 'Found',
      303 => 'See Other',
      304 => 'Not Modified',
      305 => 'Use Proxy',
      307 => 'Temporary Redirect',
      400 => 'Bad Request',
      401 => 'Unauthorized',
      402 => 'Payment Required',
      403 => 'Forbidden',
      404 => 'Not Found',
      405 => 'Method Not Allowed',
      406 => 'Not Acceptable',
      407 => 'Proxy Authentication Required',
      408 => 'Request Timeout',
      409 => 'Conflict',
      410 => 'Gone',
      411 => 'Length Required',
      412 => 'Precondition Failed',
      413 => 'Request Entity Too Large',
      414 => 'Request-URI Too Large',
      415 => 'Unsupported Media Type',
      416 => 'Request Range Not Satisfiable',
      417 => 'Expectation Failed',
      500 => 'Internal Server Error',
      501 => 'Not Implemented',
      502 => 'Bad Gateway',
      503 => 'Service Unavailable',
      504 => 'Gateway Timeout',
      505 => 'HTTP Version Not Supported'
    }

    ZMQ_RESP = "%s %d:%s, %s".freeze
    HTTP_HEADER = "HTTP/1.1 %s %s\r\n%s\r\n\r\n".freeze
    HTTP_HEADER_KEY_VAL = "%s: %s".freeze

    def initialize(resp)
      @resp = resp
    end

    def send_http(req, body, status, headers)
      send_resp(req.uuid, req.conn_id, build_http_headers(status, headers))

      if body.respond_to?(:each)
        body.each do |b|
          send_resp(req.uuid, req.conn_id, b) unless b == ''
        end
      else
        send_resp(req.uuid, req.conn_id, body.to_s)
      end

      body.close if body.respond_to?(:close)
    end

    def close(req)
      send_resp(req.uuid, req.conn_id, '')
    end

    private

    def send_resp(uuid, conn_id, data)
      @resp.send_msg(ZMQ_RESP % [uuid, conn_id.size, conn_id, data])
    end

    def build_http_headers(status, headers)
      headers = headers.map { |k, vs|
            vs.split("\n").map { |v| HTTP_HEADER_KEY_VAL % [k, v] }
          }.join("\r\n")
      HTTP_HEADER % [status, StatusMessage[status.to_i], headers]
    end

  end
end
