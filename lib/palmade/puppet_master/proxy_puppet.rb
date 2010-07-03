module Palmade::PuppetMaster
  class ProxyPuppet < Palmade::PuppetMaster::EventdPuppet
    DEFAULT_OPTIONS = {
      # to, accepts any connections
      # - host:port
      # - /tmp/some.sock
      :to => nil,
      :idle_time => 5
    }

    class ClientConnection < EventMachine::Connection
      attr_accessor :puppet
      attr_accessor :blind

      def initialize
        @puppet = nil
        @proxy_conn = nil
      end

      def post_init
      end

      def receive_data(data)
        if @proxy_conn.nil?
          # only supports data for connecting
          to, error = @puppet.infer(data)
          unless to.nil?
            @proxy_conn = create_proxy(to)
            @proxy_conn.send_data(data) #if @blind
          else
            send_data(error)
            close_connection
          end
        else
          @proxy_conn.send_data(data)
        end
      end

      # if the other end has closed their connection
      def proxy_target_unbound
        @proxy_conn = nil
        close_connection
      end

      def unbind
        unless @proxy_conn.nil?
          @proxy_conn.close_connection_after_writing rescue nil
          @proxy_conn = nil
        end
        @puppet.connection_finished(self)
      end

      protected

      def create_proxy(to)
        if to[0] == ?/
          host = to
          port = nil
        else
          host, port = to.split(':')
        end

        EventMachine.connect(host, port, ProxyConnection, self)
      end
    end

    class ProxyConnection < EventMachine::Connection
      def initialize(client)
        @client = client
      end

      def post_init
        # let's enable bi-directional flow
        EventMachine.enable_proxy(@client, self)
        EventMachine.enable_proxy(self, @client)
      end

      def proxy_target_unbound
        close_connection
      end

      def unbind
        @client.close_connection_after_writing rescue nil
      end
    end

    def initialize(options = { }, &block)
      super(DEFAULT_OPTIONS.merge(options), &block)

      if @proc_tag.nil?
        @proc_tag = "proxy"
      else
        @proc_tag = "proxy.#{@proc_tag}"
      end

      @listen_key = nil
      @sockets = nil
      @signatures = nil
      @connections = [ ]
      @stopping = false

      @connection_klass = ClientConnection
    end

    def after_fork(w)
      super(w)
      master = w.master

      # let's set the sockets with the proper settings for
      # attaching as acceptors to EventMachine
      if master.listeners[@listen_key].nil? || master.listeners[@listen_key].empty?
        raise ArgumentError, "No configured #{@listen_key || 'default'} listeners from master"
      else
        @sockets = master.listeners[@listen_key]
        raise ArgumentError, "Nothing to do, no sockets defined in master" if @sockets.nil? || @sockets.empty?
      end

      # * FD_CLOEXEC <-- this is done on the worker class (init method)
      # * SO_REUSEADDR <-- TODO: figure out why we need this? couldn't find it in unicorn
      # * Set non-blocking <--
      @sockets.each do |s|
        s.fcntl(Fcntl::F_SETFL, Fcntl::O_NONBLOCK)
      end
    end

    def work_loop(worker, ret = nil, &block)
      master_logger.warn "proxy worker #{worker.proc_tag} started: #{$$}"

      # trap(:USR1) {  } do nothing, it should reload logs
      trap(:QUIT) { stop_work_loop(worker) }
      [ :TERM, :INT ].each { |sig| trap(sig) { stop_work_loop(worker, true) } } # instant shutdown

      EventMachine.run do
        EventMachine.epoll rescue nil
        EventMachine.kqueue rescue nil

        # do some work
        if block_given?
          yield(self, worker)
        elsif !@work_loop.nil?
          @work_loop.call(self, worker)
        else
          start!
        end

        EventMachine.add_timer(@options[:idle_time]) { idle_time(worker) }
      end
      worker.stop!
      stop

      master_logger.warn "proxy worker #{worker.proc_tag} stopped: #{$$}"

      ret
    end

    def stop_work_loop(worker, now = false)
      worker.stop!

      if now
        stop!
      else
        stop
      end
    end

    # infer data sent by client
    def infer(data)
      to = nil

      if @options[:to].nil?
        error = "-ERR Not implemented\r\n"
      else
        if @options[:to].is_a?(Array)
          @round = 0 unless defined?(@round)

          to = @options[:to][@round]
          error = nil

          if @round == @options[:to].size - 1
            @round = 0
          else
            @round += 1
          end
        else
          to = @options[:to]
          error = nil
        end
      end

      [ to, error ]
    end

    # Called by a connection when it's unbinded.
    def connection_finished(connection)
      @connections.delete(connection)
    end

    protected

    def stop
      @stopping = true
      @signatures.each do |s|
        EventMachine.stop_accept(s)
      end unless @signatures.empty? || !EventMachine.reactor_running?

      # we just stop right away, since
      # we're a blind proxy, we don't know what's going on
      # in the pipes
      stop!
    end

    def stop!
      if EventMachine.reactor_running?
        # we dup here, since the connection_finished hook above
        # might be called every time we call close_connection
        @connections.dup.each { |connection| connection.close_connection } unless @connections.empty?

        EventMachine.stop_event_loop
      end
    end

    def start!
      @signatures = @sockets.collect do |s|
        EventMachine.accept(s, @client_connection, &method(:initialize_connection))
      end unless @sockets.nil?
    end

    def initialize_connection(connection)
      connection.puppet = self
      @connections << connection
    end

    def idle_time(w)
      if w.ok?
        w.alive!
        EventMachine.add_timer(@options[:idle_time]) { idle_time(w) }
      end
    end
  end
end
