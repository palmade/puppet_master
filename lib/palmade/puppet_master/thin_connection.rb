# -*- encoding: utf-8 -*-

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

      # initialize web socket connection state to :handshake. this is
      # the default state, irregardless if this is a websocket
      # connection or not.
      #
      # other states are :
      #
      #   :connected
      #   :terminated
      #   :unbinded
      #
      # the :terminated state will not be on for a long time, since
      # this is the last state to set the connection to, when the
      # connection is about to go down. :unbinded is when the
      # connection has already been disconnected (set when unbind is
      # called by eventmachine)
      @ws_state = :handshake
      @ws_handler = nil

      super
    end

    # TODO: Add support for upgrading this connection to a WebSocket
    # See: http://github.com/laktek/Web-Socket-Examples/blob/master/websocket_server.rb
    def process
      if websocket?
        # TODO: Add exception handling here
        @ws_handler.process(@request.body)
      else
        working!
        super
      end
    end

    def terminate_request
      not_working!

      if websocket?
        # do nothing, normally thin will close both request and
        # response objects, and then re-initializes them to a new
        # instance. For websockets, we'll keep them in the connection
        # object for now, for the duration of the web socket
        # connections.
        #
        # A big warning here to avoid lingering unnecessary objects in
        # memory. and also possible leaks.
      else
        super
      end
    end

    def post_process(result)
      return unless result
      # Status code -1 indicates that we're going to respond later (async).
      return if (result = result.to_a).first == AsyncResponse.first

      # based on the result, let's check if we're requesting the
      # client to upgrade to WebSocket, if so, let's change our state
      # to that. The 'result', maybe also contain the receive_data and
      # send_data handler, that we will attach to this connection.
      websocket_upgrade!(result) if websocket_upgrade?(result)

      super
      puppet.post_process(self, worker) unless puppet.nil?
    end

    def websocket?
      persistent? && websocket_connected?
    end

    def terminate_websocket
      cant_persist!
      @ws_state = :terminated

      terminate_request
    end

    def unbind
      # we have a ws_handler set, and we'd like to notify it that the
      # connection is it related to, has been disconnected or no
      # longer servicable.
      #
      # this is a default check, no need to check the ws_state, since
      # unbind can be called either the client side initiated the
      # disconnection or via the terminated_request method. either
      # way, if we have a connected ws_handler, we should notify it.
      unless @ws_handler.nil?
        @ws_handler.unbind(self)
        @ws_handler = nil
        @ws_state = :unbinded
      end

      super
    end

    protected

    CWebSocket = "WebSocket".freeze
    CUpgrade = "Upgrade".freeze
    CConnection = "Connection".freeze
    def websocket_upgrade?(result)
      headers = result[1]
      if headers[CUpgrade] == CWebSocket &&
          headers[CConnection] == CUpgrade
        true
      else
        false
      end
    end

    # from the result (Array), the websocket handler (sort of
    # functions just like an EventMachine connection)
    # TODO: Add support for setting the @ws_handler object
    def websocket_upgrade!(result)
      @ws_state = :connected
    end

    def websocket_connected?
      @ws_state == :connected
    end
  end
end
