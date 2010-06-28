module Palmade::PuppetMaster
  class ServiceQueue < Palmade::PuppetMaster::Service
    cattr_accessor :beanstalkd_path
    self.beanstalkd_path = `which beanstalkd`.strip

    DEFAULT_OPTIONS = {
      :listen_host => '127.0.0.1',
      :listen_port => nil
    }

    def initialize(master, service_name = nil, options = { })
      super(master, service_name || :queue, DEFAULT_OPTIONS.merge(options))

      @listen_port = @options[:listen_port]
      @listen_host = @options[:listen_host]
    end

    def start
      if @listen_port.nil?
        @listen_port = find_available_port
      end
      @master.reserved_ports.add(@listen_port)

      logger.warn "#{@service_name} listen on: #{@listen_host}:#{@listen_port}"

      cmd = "#{beanstalkd_path} -l #{@listen_host} -p #{@listen_port}"
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

    def reset
      unless @client.nil?
        client.close
        client.connect
      end
    end

    def client_reset
      unless @client.nil?
        @client.close
        @client = nil
        client
      end
    end

    def client
      if @client.nil? && !@disabled
        Palmade::PuppetMaster.require_beanstalk

        logger.warn "#{@service_name} client connect: #{@listen_host}:#{@listen_port}"
        @client = Beanstalk::Pool.new("#{@listen_host}:#{@listen_port}")
      else
        @client
      end
    end

    def close
      client.close unless @client.nil?
    end
  end
end
