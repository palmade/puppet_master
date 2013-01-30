module Palmade::PuppetMaster
  class ControlPort
    def initialize(options = {})
      @master   = options[:master]
      @socket   = options.fetch(:socket)
      @logger   = options[:logger]
      @options  = options

      start_server
    end

    def start_server
      @logger.info { "control port started: #{@socket.path}" }

      @instance =
        Thread.new do
          loop do
            Thread.start(@socket.accept) do |client|
              begin
                while client.gets
                  process_command(client, $_)
                end
              rescue IOError => e
                raise unless e.message == 'closed stream'
              rescue ArgumentError => e
                client.write "%s\n" % e.message
                retry
              end

            end
          end
        end

    end

    def stop
      @logger.info { "control port stopped" }
      @instance.exit

      File.unlink(@socket.path) if File.exists?(@socket.path)
      @socket.close
    end

    private

    def process_command(client, command)
      raise ArgumentError, 'Unknown command' unless valid_command? command

      case command.strip[1..-1]
      when 'stats'
        client.write stats
      when 'quit'
        client.close
      else
        raise ArgumentError, 'Unknown command'
      end
    end

    def valid_command?(command)
      !!(command =~ /^!/)
    end

    def stats
      master_pid  = @master.pid
      worker_pids = workers.map(&:keys).join(" ")

      "#{format_master_info}\n" \
        "workers #{worker_pids}\n" \
        "#{format_workers_info}\n"
    end

    def format_master_info
      "master %d up %s" % [@master.pid,
                           seconds_in_words(@master.uptime)]

    end

    def format_workers_info
      workers.map do |w_hash|
        w_hash.map do |(pid, worker)|
          "worker %d up %s pi %s" % [pid,
                                     seconds_in_words(worker.uptime),
                                     seconds_in_words(worker.last_ping)]
        end.join("\n")
      end.flatten.join
    end

    def workers
      @master.family.puppets.values.map(&:workers)
    end

    # Converts Time represented as a number in words with the following
    # format dd day(s), hh:mm:ss omits "dd days" if dd if 0
    #
    def seconds_in_words(time)
      mm, ss = time.divmod(60)
      hh, mm = mm.divmod(60)
      dd, hh = hh.divmod(24)

      words = ""
      words << "%d day%s, " % [dd, dd > 1 ? "s":""] if dd > 0
      words << "%02d:" % hh
      words << "%02d:" % mm
      words << "%02d"  % ss
      words
    end

  end
end
