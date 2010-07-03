module Palmade::PuppetMaster
  class ServiceRedis < Palmade::PuppetMaster::Service
    def self.redis_path; @@redis_path; end
    def self.redis_path=(rp); @@redis_path = rp; end
    self.redis_path = `which redis-server`.strip

    DEFAULT_OPTIONS = {
      :listen_host => '127.0.0.1',
      :listen_port => nil,
      :client_options => { },
    }

    def initialize(master, service_name = nil, options = { })
      super(master, service_name || :redis, DEFAULT_OPTIONS.merge(options))

      @listen_port = @options[:listen_port]
      @listen_host = @options[:listen_host]

      @temp_files = { }
    end

    def start
      if @listen_port.nil?
        @listen_port = find_available_port
      end
      @master.reserved_ports.add(@listen_port)

      logger.warn "#{@service_name} listening on: #{@listen_host}:#{@listen_port}"

      conf_file = write_temporary_conf_file
      cmd = "#{self.class.redis_path} #{conf_file}"
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
        Palmade::PuppetMaster.require_redis

        logger.warn "#{@service_name} client connect: #{@listen_host}:#{@listen_port}"
        @client = Redis.new(@options[:client_options].update(:host => @listen_host, :port => @listen_port))
      else
        @client
      end
    end

    def client_reset
      close unless @client.nil?
      @client = nil
      client
    end

    def reset
      unless @client.nil?
        @client.client.reconnect
      end
    end

    def close
      unless @client.nil?
        @client.quit
      end
    end

    protected

    def write_temporary_conf_file
      conf_file = @temp_files[:conf_file] = "#{Dir::tmpdir}/#{service_id_path_safe}.conf"
      db_file = @temp_files[:db_file] = "#{Dir::tmpdir}/#{service_id_path_safe}.rdb"
      log_file = @temp_files[:log_file] = service_log_file

      cleanup_temporary_files
      File.open(conf_file, "w") do |f|
        f.puts "port #{@listen_port}"
        f.puts "bind #{@listen_host}"
        f.puts "pidfile #{service_pid_file}"
        f.puts "dbfilename #{File.basename(db_file)}"
        f.puts "dir #{Dir::tmpdir}"
        f.puts "loglevel notice"
        f.puts "logfile #{log_file}"
      end

      conf_file
    end

    def stop
      kill(:TERM)
    end
  end
end
