Feature: master can be started

  As a user
  I want to start the master
  So that it will serve my needs

  Scenario: started as a daemon
    Given a directory named "config"
    And a directory named "script"
    And a directory named "tmp/pids"
    And a directory named "log"
    And a file named "config/appctl.yml" with:
    """
    listen:
      - 0.0.0.0:22222

    tail: false

    environment: testing

    tag: testing

    pid_file: tmp/pids/appctl.pid

    log_file: log/appctl.log

    epoll: true
    """
    And a file named "config/appctl.rb" with:
    """
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
      count = 1

      m.proc_tag = proc_tag
      fam.puppet(:proc_tag => proc_tag,
                 :adapter => MockAdapter,
                 :adapter_options => config.symbolize_keys,
                 :count => count)
    end

    module MockAdapter
    end
    """
    And a file named "script/appctl" with:
    """
    #!/usr/bin/env ruby

    require 'rubygems'
    require 'bundler/setup'

    require 'palmade/puppet_master'

    Palmade::PuppetMaster.runner!(ARGV)
    """
    And a file named "config.ru" with:
    """
    run lambda { |env| [200, {'Content-Type'=>'text/plain'}, StringIO.new("Hello World!\n")] }
    """
    And there are no other instances running
    When I run `ruby script/appctl start`
    Then the exit status should be 0
    And it should run as a daemon
    And the following files should exist:
      | tmp/pids/appctl.pid |
      | log/appctl.log |
    And the file "tmp/pids/appctl.pid" should contain the pid

  Scenario: started as a daemon with another instance already running
    Given a puppet_master instance is running
    When I run `ruby script/appctl start`
    Then it should fail with:
    """
    already running
    """
