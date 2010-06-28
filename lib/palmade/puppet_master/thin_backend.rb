module Palmade::PuppetMaster
  class ThinBackend < Thin::Backends::Base
    attr_accessor :sockets
    attr_accessor :puppet
    attr_accessor :worker
    attr_accessor :max_current_connections

    include Thin::Logging

    def initialize(host, port, options = { })
      unless EventMachine.respond_to?(:accept)
        raise "Please use the patched event_machine that supports pre-binded sockets"
      end

      super()

      @connected = false
      @sockets = [ ]
      @signatures = [ ]
    end

    def connect
      return if @connected

      @signatures = @sockets.collect do |s|
        EventMachine.accept(s, Palmade::PuppetMaster::ThinConnection, &method(:initialize_connection))
      end
      @connected = true
      @signatures
    end

    def disconnect
      return unless @connected

      @signatures.each do |s|
        EventMachine.stop_accept(s)
      end
      @connected = false
      @signatures
    end

    def to_s
      @sockets.collect { |sock| Palmade::PuppetMaster::SocketHelper.sock_name(sock) }.join(',')
    end

    def connection_finished(connection)
      super
      puppet.connection_finished(connection, worker)

      # no need to check if we are stopping
      check_max_current_connections unless @stopping
    end

    def initialize_connection(connection)
      super
      check_max_current_connections unless @stopping

      connection.puppet = puppet
      connection.worker = worker
    end

    def port
      nil
    end

    protected

    def check_max_current_connections
      if maxed?
        if @connected
          disconnect
        end
      else
        unless @connected
          connect
        end
      end
    end

    def maxed?
      !max_current_connections.nil? && size >= max_current_connections
    end
  end
end
