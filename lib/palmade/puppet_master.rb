PUPPET_MASTER_LIB_DIR = File.dirname(__FILE__) unless defined?(PUPPET_MASTER_LIB_DIR)
PUPPET_MASTER_ROOT_DIR = File.join(PUPPET_MASTER_LIB_DIR, '../..') unless defined?(PUPPET_MASTER_ROOT_DIR)

require 'rubygems'

require 'fcntl'
require 'tmpdir'
require 'socket'
require 'optparse'
require 'set'
require 'syslog'
require 'logger'
require 'timeout'

require File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/syslogger')
require File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/sysloggerio')

gem 'eventmachine'
require 'eventmachine'

module Palmade
  module PuppetMaster
    def self.logger;     @logger    ; end
    def self.logger=(l); @logger = l; end
    def self.master;     @master    ; end
    def self.master=(m); @master = m; end

    # main classes
    autoload :Master, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/master')
    autoload :Puppets, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/puppets')
    autoload :Family, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/family')
    autoload :Worker, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/worker')

    # auxilliary services
    autoload :ControlPort, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/control_port')
    autoload :Service, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/service')
    autoload :ServiceRedis, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/service_redis')

    # common set of launchers
    autoload :Config, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/config')
    autoload :Configurator, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/configurator')
    autoload :Runner, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/runner')
    autoload :Controller, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/controller')

    # utilities and misc
    autoload :SocketHelper, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/socket_helper')
    autoload :Utils, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/utils')
    autoload :Dependencies, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/dependencies')

    # mixins
    autoload :Mixins, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/mixins')

    # for backwards compatibility
    EventdPuppet   = Puppets::EventdPuppet
    Puppet         = Puppets::Base

    def self.run!(options = { }, &block)
      raise "You can't run multiple masters in the same process!" unless master.nil?
      m = self.master = Palmade::PuppetMaster::Master.new(options)
      if block_given?
        yield m
        m.start.join
      else
        m
      end
    end

    def self.runner!(argv, options = { }, &block)
      r = Palmade::PuppetMaster::Runner.new(argv, options, &block)
      r.run.doit!
    end

    def self.services
      unless self.master.nil?
        self.master.services
      end
    end
  end
end
