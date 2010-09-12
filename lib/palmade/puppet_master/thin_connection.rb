# -*- encoding: binary -*-

module Palmade::PuppetMaster
  class ThinConnection < Thin::Connection
    attr_accessor :puppet
    attr_accessor :worker

    def working?; @working ||= false; end
    def working!; @working = true; end
    def not_working!; @working = false; end

    def cant_persist!; @can_persist = false; end

    def post_init
      not_working!
      super
    end

    def process
      working!
      super
    end

    def terminate_request
      not_working!
      super
    end

    def post_process(result)
      return unless result

      # Status code -1 indicates that we're going to respond later (async).
      if (result = result.to_a).first == -1
        # this is added here to support the rails reloader when in
        # development mode. it attaches a body wrap, that expects the
        # web server to call the 'close' method on the body
        # provided. to finish the request, which triggers the
        # reloader to unload dynamically loaded objects and unlock the
        # global mutex.
        result.last.close if result.last.respond_to?(:close)

        return
      end

      # based on the result, let's check if we're requesting the
      # client to upgrade to WebSocket, if so, let's change our state
      # to that. The 'result', maybe also contain the receive_data and
      # send_data handler, that we will attach to this connection.
      websocket_upgrade!(result) if websocket_upgrade?(result)

      # The result object at this point is already an Array. we just
      # called .to_a, which in Rack::Response, also works as 'finish'
      # method. To avoid double-finishing our result, we just call it
      # once here.
      ret = super(result)
      puppet.post_process(self, worker) unless puppet.nil?

      ret
    end

    protected

    CWebSocket = "WebSocket".freeze
    CUpgrade = "Upgrade".freeze
    CConnection = "Connection".freeze

    def websocket_upgrade?(result)
      status = result[0].to_i
      headers = result[1]

      # "HTTP/1.1 101 Web Socket Protocol Handshake\r\n"
      if status == 101 && headers[CConnection] == CUpgrade &&
          headers[CUpgrade] == CWebSocket
        true
      else
        false
      end
    end

    def websocket_upgrade!(result)
      # let's add the web socket extensions to this connection instance
      self.extend(Palmade::PuppetMaster::ThinWebsocketConnection)
      websocket_upgrade!(result)
    end
  end
end
