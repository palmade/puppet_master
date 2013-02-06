Given /^there are (\d+) ?(.+)? workers$/ do |n, type|
  t_dir     = File.join(File.expand_path('../../..', __FILE__), 't')
  @child_pids = Array.new

  stdout = Utils.start_master(n, type)
  @master_pid = stdout.pid
  Utils.wait_master_ready(stdout)
  Utils.wait_workers_ready(stdout, n.to_i)

  @child_pids = Utils.get_child_pids(@master_pid)

  at_exit do
    stdout.close
  end
end

When /^the master dies$/ do
  Process.kill(:KILL, @master_pid)
  Process.waitpid(@master_pid)
end

Then /^all workers should die within a minute$/ do
  @child_pids.each do |child_pid|
    t0 = Time.now
    expect {
      loop do
        Process.kill(0, child_pid.to_i); sleep 0.2
        break if (Time.now - t0) > 60
      end
    }.to raise_error Errno::ESRCH
    (Time.now - t0).should be < 60
  end
end

Given "there are no other instances running" do
  cmd = "appctl master[cucumber-puppet_master.testing] start"
  pid = get_pid(cmd) and terminate(pid)
end

Then /^it should run as a daemon$/ do
  cmd = "appctl master[cucumber-puppet_master.testing] start"
  get_tty(cmd).should eql '?'
end


Then /^the file "([^"]*)" should contain the pid$/ do |pid_file|
  cmd = "appctl master[cucumber-puppet_master.testing] start"
  pid = get_pid(cmd)
  step "the file \"#{pid_file}\" should contain \"#{pid}\""
end
