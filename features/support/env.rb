require 'rubygems'
require 'bundler/setup'
require 'aruba/cucumber'

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

  def get_master_pid
    master_pid_file = File.join(t_dir, 'tmp', 'pids', 'appctl.pid')
    File.read(master_pid_file)
  end

  def get_pid(cmd)
    pid = get_ps_info(cmd)[:pid]
    pid and pid.to_i
  end

  def get_tty(cmd)
    get_ps_info(cmd)[:tty]
  end

  def get_ps_info(cmd)
    ps              = "ps -eo pid,tty,cmd"
    cmd_pattern     = Regexp.escape(cmd)
    ps_line_pattern = '(?<pid>\d+)\s+(?<tty>\S)\s+' + cmd_pattern

    run_simple(unescape(ps))
    output_from(ps).match(Regexp.new(ps_line_pattern)) or {}
  end

  def terminate(pid)
    Process.kill(:QUIT, pid)

    begin
      Timeout.timeout(60) do
        sleep 0.2 while Process.getpgid(pid) != -1
      end
    rescue Timeout::Error
      Process.kill(:KILL, pid)
    rescue Errno::ESRCH
    end
  end
end

World(Utils)

After do |scenario|
  cmd = "appctl master[cucumber-puppet_master.testing] start"
  pid = get_pid(cmd) and terminate(pid)
end
