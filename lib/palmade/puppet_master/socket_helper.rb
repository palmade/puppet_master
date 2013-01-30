module Palmade::PuppetMaster
  module SocketHelper
    include Socket::Constants

    # configure platform-specific options (only tested on Linux 2.6 so far)
    case RUBY_PLATFORM
    when /linux/
      # from /usr/include/linux/tcp.h
      TCP_DEFER_ACCEPT = 9 unless defined?(TCP_DEFER_ACCEPT)
      TCP_CORK = 3 unless defined?(TCP_CORK)
    when /freebsd(([1-4]\..{1,2})|5\.[0-4])/
      # Do nothing for httpready, just closing a bug when freebsd <= 5.4
      TCP_NOPUSH = 4 unless defined?(TCP_NOPUSH)
    when /freebsd/
      TCP_NOPUSH = 4 unless defined?(TCP_NOPUSH)
      # Use the HTTP accept filter if available.
      # The struct made by pack() is defined in /usr/include/sys/socket.h
      # as accept_filter_arg
      unless `/sbin/sysctl -nq net.inet.accf.http`.empty?
        FILTER_ARG = ['httpready', nil].pack('a16a240')
      end
    end

    def self.set_tcp_sockopt(sock, opt)
      # highly portable, but off by default because we don't do keepalive
      if defined?(TCP_NODELAY) && ! (val = opt[:tcp_nodelay]).nil?
        sock.setsockopt(IPPROTO_TCP, TCP_NODELAY, val ? 1 : 0) rescue nil
      end

      unless (val = opt[:tcp_nopush]).nil?
        val = val ? 1 : 0
        if defined?(TCP_CORK) # Linux
          sock.setsockopt(IPPROTO_TCP, TCP_CORK, val) rescue nil
        elsif defined?(TCP_NOPUSH) # TCP_NOPUSH is untested (FreeBSD)
          sock.setsockopt(IPPROTO_TCP, TCP_NOPUSH, val) rescue nil
        end
      end

      # No good reason to ever have deferred accepts off
      if defined?(TCP_DEFER_ACCEPT)
        sock.setsockopt(SOL_TCP, TCP_DEFER_ACCEPT, 1) rescue nil
      elsif defined?(SO_ACCEPTFILTER) && defined?(FILTER_ARG)
        sock.setsockopt(SOL_SOCKET, SO_ACCEPTFILTER, FILTER_ARG) rescue nil
      end
    end

    def self.set_server_sockopt(sock, opt = nil)
      opt ||= {}

      TCPSocket === sock and set_tcp_sockopt(sock, opt)

      if opt[:rcvbuf] || opt[:sndbuf]
        #log_buffer_sizes(sock, "before: ")
        sock.setsockopt(SOL_SOCKET, SO_RCVBUF, opt[:rcvbuf]) if opt[:rcvbuf]
        sock.setsockopt(SOL_SOCKET, SO_SNDBUF, opt[:sndbuf]) if opt[:sndbuf]
        #log_buffer_sizes(sock, " after: ")
      end

      sock.listen(opt[:backlog] || 1024)
    end

    # commented out, since we don't support logger in this module
    #def self.log_buffer_sizes(sock, pfx = '')
    #  respond_to?(:logger) or return
    #  rcvbuf = sock.getsockopt(SOL_SOCKET, SO_RCVBUF).unpack('i')
    #  sndbuf = sock.getsockopt(SOL_SOCKET, SO_SNDBUF).unpack('i')
    #  logger.info "#{pfx}#{sock_name(sock)} rcvbuf=#{rcvbuf} sndbuf=#{sndbuf}"
    #end

    def self.listen(address = nil, opt = { })
      return nil if address.nil?
      return address unless String === address

      sock = nil
      if address =~ /^(\d+\.\d+\.\d+\.\d+):(\d+)$/
        sock = TCPServer.new($1, $2.to_i)
      else
        if File.exist?(address)
          if File.socket?(address)
            File.unlink(address)
          else
            raise ArgumentError, "socket=#{address} specified but it is not a socket!"
          end
        end

        old_umask = File.umask(0)
        begin
          sock = UNIXServer.new(address)
        ensure
          File.umask(old_umask)
        end
      end

      set_server_sockopt(sock, opt) unless sock.nil?
      sock
    end

    # Returns the configuration name of a socket as a string.  sock may
    # be a string value, in which case it is returned as-is
    # Warning: TCP sockets may not always return the name given to it.
    def self.sock_name(sock)
      case sock
      when String then sock
      when UNIXServer
        Socket.unpack_sockaddr_un(sock.getsockname)
      when TCPServer
        Socket.unpack_sockaddr_in(sock.getsockname).reverse!.join(':')
      when Socket
        begin
          Socket.unpack_sockaddr_in(sock.getsockname).reverse!.join(':')
        rescue ArgumentError
          Socket.unpack_sockaddr_un(sock.getsockname)
        end
      else
        raise ArgumentError, "Unhandled class #{sock.class}: #{sock.inspect}"
      end
    end

    def self.find_available_port(port_range, reserved_ports = Set.new)
      avail_port = nil
      s = Socket.new(Socket::Constants::AF_INET, Socket::Constants::SOCK_STREAM, 0)
      port_range.each do |p|
        next if reserved_ports.include?(p)

        saddr = Socket.pack_sockaddr_in(p, '127.0.0.1')
        begin
          s.bind(saddr)
          avail_port = p
          break
        rescue Errno::EACCES, Errno::EADDRINUSE
          next
        end
      end
      avail_port
    ensure
      s.close
    end

    # casts a given Socket to be a TCPServer or UNIXServer
    def self.server_cast(sock)
      begin
        Socket.unpack_sockaddr_in(sock.getsockname)
        TCPServer.for_fd(sock.fileno)
      rescue ArgumentError
        UNIXServer.for_fd(sock.fileno)
      end
    end
  end
end
