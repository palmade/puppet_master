Given /^there are (\d+) ?(.+)? workers$/ do |n, type|
  count  = n.to_i
  puppet =
    case type
    when 'base' then 'puppet'
    when 'thin', 'eventd', 'mongrel2'
      then "#{type}_puppet"
    end

  step 'a directory named "config"'
  step 'a directory named "script"'
  step 'a directory named "tmp/pids"'
  step 'a directory named "log"'
  step 'a file named "config/appctl.yml" with:',
<<-appctl_yml
  listen:
    - 0.0.0.0:22222

  tail: false

  environment: testing

  tag: testing

  pid_file: tmp/pids/appctl.pid

  log_file: log/appctl.log

  epoll: true

  mongrel2:
    recv: tcp://127.0.0.1:22223
    send: tcp://127.0.0.1:22224
    uuid: 534a36f1-5fcb-4636-8aa9-749fae727ad5

appctl_yml
  step 'a file named "config/appctl.rb" with:',
<<-appctl_rb
  main do |m, config, controller|
    config[:environment] = 'testing'

    call(config[:environment])
  end

  testing do |m, config, controller|
    call :common
  end

  common do |m, config, controller|
    fam = m.single_family!

    proc_tag = "cucumber-puppet_master.testing"
    count = #{count}

    m.proc_tag = proc_tag
    fam.#{puppet}(:proc_tag => proc_tag,
               :adapter => MockAdapter,
               :adapter_options => config.symbolize_keys,
               :count => count)
  end

  module MockAdapter
  end
appctl_rb
  step 'a file named "script/appctl" with:',
<<-appctl
  #!/usr/bin/env ruby

  require 'rubygems'
  require 'bundler/setup'

  require 'palmade/puppet_master'

  Palmade::PuppetMaster.runner!(ARGV)
appctl
  step 'a file named "config.ru" with:',
<<-config_ru
  run lambda { |env| [200, {'Content-Type'=>'text/plain'}, StringIO.new("Hello World!\n")] }
config_ru
  step 'there are no other instances running'
  step 'I run `ruby script/appctl start`'
  step "it should spawn #{count} workers"
end

Then /^it should spawn (\d+) worker(?:s)?$/ do |n|
  count = n.to_i
  cmd   = Regexp.escape("appctl master[cucumber-puppet_master.testing] start")

  size = nil
  Timeout.timeout(30) do
    loop do
      size = get_children(cmd).size
      sleep 0.2 if size < count
      break if size >= count
    end
  end rescue Timeout::Error

  size.should eql count
  @children = get_children(cmd)
end

When /^the master dies$/ do
  cmd = Regexp.escape("appctl master[cucumber-puppet_master.testing] start")
  pid = get_pid(cmd) and terminate(pid) rescue Errno::ESRCH
end

When /^the master dies a tragic death$/ do
  cmd = Regexp.escape("appctl master[cucumber-puppet_master.testing] start")
  pid = get_pid(cmd) and murder(pid) rescue Errno::ESRCH
end

Then /^all workers should die within a minute$/ do
  @children.each do |child|
    child_pid = child[:pid].to_i

    t0 = Time.now
    expect {
      loop do
        Process.kill(0, child_pid); sleep 0.2
        break if (Time.now - t0) > 60
      end
    }.to raise_error Errno::ESRCH
    (Time.now - t0).should be < 60
  end
end

Given "there are no other instances running" do
  cmd = Regexp.escape("appctl master[cucumber-puppet_master.testing]")
  pid = get_pid(cmd) and terminate(pid) rescue Errno::ESRCH
end

Then /^it should run as a daemon$/ do
  cmd = Regexp.escape("appctl master[cucumber-puppet_master.testing] start")
  get_tty(cmd).should eql '?'
end


Then /^the file "([^"]*)" should contain the pid$/ do |pid_file|
  cmd = Regexp.escape("appctl master[cucumber-puppet_master.testing] start")
  pid = get_pid(cmd)
  step "the file \"#{pid_file}\" should contain \"#{pid}\""
end
