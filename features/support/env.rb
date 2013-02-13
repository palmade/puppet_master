require 'rubygems'
require 'bundler/setup'
require 'aruba/cucumber'

require 'palmade/puppet_master'

DEFAULT_TRIES     = 1000
DEFAULT_TIMEOUT   = 200

module Utils
  def get_master_pid
    master_pid_file = File.join(t_dir, 'tmp', 'pids', 'appctl.pid')
    File.read(master_pid_file)
  end

  def get_pid(cmd)
    processes = get_ps_info(cmd)
    begin
      processes.size.should eql 1
    rescue RSpec::Expectations::ExpectationNotMetError
      raise Errno::ESRCH
    end

    pid = processes[0][:pid]
    pid and pid.to_i
  end

  def get_tty(cmd)
    processes = get_ps_info(cmd)
    begin
      processes.size.should eql 1
    rescue RSpec::Expectations::ExpectationNotMetError
      raise Errno::ESRCH
    end

    get_ps_info(cmd)[0][:tty] || raise(Errno::ESRCH)
  end

  def get_ps_info(cmd)
    ps              = "ps -o pid,tty,cmd -C ruby"
    ps_line_pattern = '(?<pid>\d+)\s+(?<tty>\S+)\s+(?<cmd>' + cmd + ')'

    run_simple(unescape(ps))

    info = find_matches(output_from(ps), ps_line_pattern)

    info or raise Errno::ESRCH
  end

  def get_children(cmd)
    pid = get_pid(cmd)

    ps              = "ps -o pid,tty,ppid,cmd --ppid #{pid}"
    ps_line_pattern = '(?<pid>\d+)\s+(?<tty>\S+)\s+(?<ppid>\d+)\s+'

    run_simple(unescape(ps))
    find_matches(output_from(ps), ps_line_pattern)
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

  def running?(pid)
    !!Process.kill(0, pid.to_i)
  rescue Errno::ESRCH
    false
  end

  def murder(pid)
    Process.kill(:KILL, pid)
  end

  def find_matches(haystack, needle)
    pattern = Regexp.new(needle)
    haystack.scan(pattern).map { |n| Hash[*pattern.names.map(&:to_sym).zip(n).flatten] }
  end
end

module Patterns
  def old_and_new_master_pattern
    old = Regexp.escape('(old)')
    cmd = Regexp.escape("[cucumber-puppet_master.testing]")
    "appctl master(?: #{old} )?#{cmd}"
  end

  def old_master_pattern
    Regexp.escape('appctl master (old) [cucumber-puppet_master.testing]')
  end

  def new_master_pattern
  end
end

World(Utils, Patterns)

After do |scenario|
  cmd = Regexp.escape("appctl master[cucumber-puppet_master.testing]")
  begin
    pid = get_pid(cmd) and terminate(pid)
  rescue Errno::ESRCH
  end
end

Before('@slow-reexec') do
  @slow_reexec = true
end
