# -*- encoding: utf-8 -*-

module Palmade::PuppetMaster
  module Puppets::Thin
    class Backend < Thin::Backends::Base
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
          EventMachine.accept(s, Connection, &method(:initialize_connection))
        end
        @connected = true
        @signatures
      end

      def disconnect
        return unless @connected

        @signatures.each do |s|
          EventMachine.stop_accept(s) if EventMachine.reactor_running?
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

        self
      end

      def initialize_connection(connection)
        super
        check_max_current_connections unless @stopping

        connection.puppet = puppet
        connection.worker = worker

        self
      end

      def port; nil; end

      def stop
        super

        # let's check if we have persistent connections that we'd like
        # to close. the *super* stop above only stops accepting new
        # connections. but persistent ones still exists. this part goes
        # through each persistent connections and kills them if it's
        # sitting idle (not working).
        unless @connections.empty?
          @connections.each do |c|
            if c.working?
              c.cant_persist!
            else
              c.close_connection
            end
          end
        end

        stop! if @connections.empty?

        self
      end

      protected

      def check_max_current_connections
        if maxed?
          disconnect if @connected
        else
          connect unless @connected
        end
      end

      def maxed?
        !max_current_connections.nil? && size >= max_current_connections
      end
    end
  end
end
