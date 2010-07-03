module Palmade::PuppetMaster
  class Service
    USE_RANDOM_PORTS = [ 44000, 45000 ]
    DEFAULT_OPTIONS = { }

    attr_reader :logger
    attr_reader :alive
    alias :alive? :alive

    attr_reader :disabled
    alias :disabled? :disabled

    def initialize(master, service_name, options = { })
      @options = DEFAULT_OPTIONS.merge(options)

      @master = master
      @service_name = service_name
      @service_pid = nil
      @client = nil
      @alive = false
      @disabled = false
      @fork_cmd = nil
    end

    def boot
      @logger = @master.logger
    end

    def service_id
      if defined?(@service_id)
        @service_id
      else
        @service_id = "#{File.basename(@master.proc_name)}-#{$$}-#{@service_name}"
      end
    end

    def start; raise "Not Implemented"; end
    def reset; raise "Not Implemented"; end
    def close; raise "Not Implemented"; end
    def client; raise "Not Implemented"; end
    def client_reset; raise "Not Implemented"; end
    def service_test; true; end

    def check_alive?
      if @service_pid.nil?
        @alive = false
      else
        if Palmade::PuppetMaster::Utils.process_running?(@service_pid)
          if service_test
            @alive = true
          else
            mark_dead!
          end
        else
          mark_dead!
        end
      end
      @alive
    end

    def reap!(master, wpid, status)
      # we just died, perhaps, we should restart?
      if wpid == @service_pid
        logger.warn "reaped #{status.inspect} service=#{@service_name}"
        mark_dead!

        cleanup_temporary_files
        true
      else
        false
      end
    end

    def stop
      kill('TERM')
    end

    def kill(signal)
      return if @service_pid.nil?
      begin
        #logger.warn "killing #{@service_name} #{@service_pid} with #{signal}"
        Process.kill(signal, @service_pid) unless @service_pid.nil?
      rescue Errno::ESRCH
        mark_dead!
      end
    end

    def mark_dead!
      @service_pid = nil
      @alive = false
    end

    def fork
      logger.warn "forking #{@service_name}"
      Kernel.fork
    end

    def work
      @master.detach_listeners_from_master
      @master.resign!(nil, "service[#{@service_name}]")
      @master.close_services

      logger.warn "master shutting down, for exec #{@fork_cmd.inspect}"
      @master.shutdown_application!(self)
      @master.shutdown!

      if @fork_cmd.is_a?(Array)
        exec(*@fork_cmd)
      else
        exec(@fork_cmd)
      end
    end

    protected

    def service_id_path_safe
      service_id.gsub(/[\/\.]/, '-')
    end

    def service_sock_file
      File.join(Dir::tmpdir, "#{service_id_path_safe}.sock")
    end

    def service_pid_file
      File.join(Dir::tmpdir, "#{service_id_path_safe}.pid")
    end

    def service_log_file
      File.join(Dir::tmpdir, "#{service_id_path_safe}.log")
    end

    def fork_service(*cmd)
      @fork_cmd = cmd
      @master.fork(self, true) do |pid|
        @service_pid = pid.to_i

        sleep(1)
        check_alive?
      end
    end

    def find_available_port
      Palmade::PuppetMaster::SocketHelper.find_available_port(USE_RANDOM_PORTS[0]...USE_RANDOM_PORTS[1],
                                                              @master.reserved_ports)
    end

    def cleanup_temporary_files
      @temp_files.each_value do |f|
        File.delete(f) if File.exist?(f)
      end if defined?(@temp_files) && !@temp_files.empty?

      [ service_sock_file, service_pid_file, service_log_file ].each do |f|
        if File.exists?(f)
          File.delete(f) rescue nil
        end
      end
    end
  end
end
