module Palmade::PuppetMaster
  class ServiceCache < Palmade::PuppetMaster::Service
    def self.memcached_path; @@memcached_path; end
    def self.memcached_path=(mp); @@memcached_path = mp; end
    self.memcached_path = `which memcached`.strip

    DEFAULT_OPTIONS = {
      # if listen_host is nil, then use unix sockets
      # Ruby memcache client don't support this!
      # :listen_host => nil,
      :listen_host => '127.0.0.1'.freeze,
      :listen_port => nil,
      :max_memory => 16,
      :client_options => { },
      :thnum => 2
    }

    def initialize(master, service_name = nil, options = { })
      super(master, service_name || :cache, DEFAULT_OPTIONS.merge(options))

      @listen_port = @options[:listen_port]
      @listen_host = @options[:listen_host]
    end

    def start
      cmd = "#{self.class.memcached_path} -P #{service_pid_file} -U 0 -m #{@options[:max_memory]} -t #{@options[:thnum]}"
      unless @listen_host.nil?
        if @listen_port.nil?
          @listen_port = find_available_port
        end
        @master.reserved_ports.add(@listen_port)

        logger.warn "#{@service_name} listen on: #{@listen_host}:#{@listen_port}"
        cmd += " -l #{@listen_host} -p #{@listen_port}"
      else
        @listen_host = service_sock_file
        cmd += " -s #{@listen_host}"
      end

      fork_service(cmd)
    end

    def reap!(*args)
      if super(*args)
        if @options[:listen_port].nil?
          @master.reserved_ports.delete(@listen_port)
          @listen_port = nil
        end
      end
    end

    def client
      if @client.nil? && !@disabled
        Palmade::PuppetMaster.require_memcache

        logger.warn "#{@service_name} client connect: #{@listen_host}:#{@listen_port}"
        @client = MemCache.new("#{@listen_host}:#{@listen_port}", @options[:client_options])
      else
        @client
      end
    end

    def client_reset
      unless @client.nil?
        @client.close
        @client = nil
        client
      end
    end

    def reset
      client.reset unless @client.nil?
    end

    def close
      client.close unless @client.nil?
    end
  end
end
