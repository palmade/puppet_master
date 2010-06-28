module Palmade::PuppetMaster
  class ServiceTokyoCabinet < Palmade::PuppetMaster::Service
    cattr_accessor :ttserver_path
    self.ttserver_path = `which ttserver`.strip

    DEFAULT_OPTIONS = {
      :listen_host => nil,
      :listen_port => nil,
      :client_options => { },
      :stealth => true,

      :thnum => 2,

      :schema => :hash,

      :schema_options => {
#        :capsiz => 16 * (1024 * 1024), # 16MB
#        :capnum => 100000
      }
    }

    def initialize(master, service_name = nil, options = { })
      super(master, service_name || :tokyo_cabinet, DEFAULT_OPTIONS.merge(options))

      @listen_port = @options[:listen_port]
      @listen_host = @options[:listen_host]

      @temp_files = { }
    end

    def start
      cmd_args = "-thnum #{@options[:thnum]} -le"
      unless @options[:stealth]
        cmd_args += " -pid #{service_pid_file} -log #{service_log_file}"
      end

      unless @listen_host.nil? || @listen_host[0] == ?/
        if @listen_port.nil?
          @listen_port = find_available_port
        end
        @master.reserved_ports.add(@listen_port)

        logger.warn "#{@service_name} listening on: #{@listen_host}:#{@listen_port}"
        cmd_args += " -host #{@listen_host} -port #{@listen_post}"
      else
        @listen_host = service_sock_file

        logger.warn "#{@service_name} listening on: #{@listen_host}"
        cmd_args += " -host #{@listen_host} -port 0"
      end

      if @options.include?(:ulog)
        cmd_args += " -ulog #{@options[:ulog]}"

        if @options.include?(:ulim)
          cmd_args += " -ulim #{@options[:ulim]}"
        end

        if @options.include?(:uas)
          cmd_args += " -uas"
        end
      end

      if @options.include?(:server_id)
        cmd_args += " -sid #{@options[:server_id]}"
      end

      if @options.include?(:ext)
        cmd_args += " -ext #{@options[:ext]}"

        if @options.include?(:extpc)
          cmd_args += " -extpc #{@options[:extpc][0]} #{@options[:extpc][1]}"
        end
      end

      if @options.include?(:db)
        dbname = "#{@options[:db]}#{schema_options}"
      else
        case @options[:schema]
        when :hash
          dbname = "*#{schema_options}"
        when :btree
          dbname = "+#{schema_options}"
        else
          raise ArgumentError, "Unknown schema: #{@options[:schema]}"
        end
      end

      fork_service(ttserver_path, *(cmd_args.strip.split(' ').push(dbname)))
    end

    def schema_options
      @options[:schema_options].keys.collect do |k|
        "##{k}=#{@options[:schema_options][k]}"
      end.join('')
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
        Palmade::PuppetMaster.require_tt

        @client = ::TokyoTyrant::RDB.new
        if @listen_host[0] == ?/
          logger.warn "#{@service_name} client connect: #{@listen_host}"
          @client.open(@listen_host)
        else
          logger.warn "#{@service_name} client connect: #{@listen_host}:#{@listen_port}"
          @client.open(@listen_host, @listen_port)
        end
      else
        check_if_alive!
      end

      @client
    end

    def client_reset
      close unless @client.nil?
      @client = nil
      client
    end

    def reset
      unless @client.nil?
        close
        reopen
      end
    end

    def close
      unless @client.nil?
        @client.close
      end
    end

    def reopen
      if @listen_host[0] == ?/
        @client.open(@listen_host)
      else
        @client.open(@listen_host, @listen_port)
      end
    end

    protected

    def check_if_alive!
      unless @client.nil?
        reset if @client.stat.nil?
      end
    end
  end
end
