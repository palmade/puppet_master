require 'rubygems'
require 'bundler/setup'

require 'palmade/puppet_master'

DEFAULT_TRIES     = 1000
DEFAULT_TIMEOUT   = 200

module Utils
  def self.wait_workers_ready(pipe, nr_workers)
    tries = DEFAULT_TRIES
    output = ""
    reg = /worker .*\d+ started\: (\d+)/

    begin
      while (tries -= 1) > 0
        IO.select([pipe], nil, nil, DEFAULT_TIMEOUT) or break
        output << pipe.readpartial(1000)

        lines = output.split("\n").grep(reg)
        lines.size == nr_workers and return lines.map { |line|
          line.match(reg)[1] }
      end
    rescue EOFError
      raise 'workers never became ready:' \
      "\n\t#{output}\n"
    end
  end

  def self.wait_master_ready(pipe)
    tries = DEFAULT_TRIES
    lines = ""

    begin
      while (tries -= 1) > 0
        IO.select([pipe], nil, nil, DEFAULT_TIMEOUT) or break
        lines << pipe.readpartial(1000)
        lines =~ /master started\:/ and return
      end
    rescue EOFError
      raise "master process never became ready:" \
      "\n\t#{lines}\n"
    end
  end

  def self.start_master(worker_count, type)
    t_dir     = File.join(File.expand_path('../../..', __FILE__), 't')
    exec_dir  = File.join(t_dir, 'bin')
    config_dir = File.join(t_dir, 'config')
    script_cmd = File.join(exec_dir, 'appctl')

    configurator =
      case type
      when 'base' then File.join(config_dir, 'puppet.rb')
      else File.join(config_dir, "#{type}.rb")
      end

    config =
      case type
      when 'mongrel2' then File.join(config_dir, 'mongrel2.yml')
      else File.join(config_dir, 'appctl.yml')
      end

    IO.popen(['ruby', script_cmd, "-s", "#{worker_count}", "-r",
              "#{configurator}", "-c", "#{t_dir}", "-C", config,
              :err => [:child, :out]])
  end

  def self.get_child_pids(ppid)
    pipe = IO.popen("ps -o pid= --ppid #{ppid}")

    pipe.readlines.inject([]) do |child_pids, line|
      child_pids << line.strip
      child_pids
    end
  end
end
