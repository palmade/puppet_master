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
    def self.logger; @logger; end
    def self.logger=(l); @logger = l; end
    def self.master; @master; end
    def self.master=(m); @master = m; end

    # main classes
    autoload :Master, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/master')
    autoload :Puppet, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/puppet')
    autoload :Family, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/family')
    autoload :Worker, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/worker')

    # types of puppets
    autoload :EventdPuppet, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/eventd_puppet')

    autoload :ThinPuppet, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/thin_puppet')
    autoload :ThinBackend, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/thin_backend')
    autoload :ThinConnection, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/thin_connection')
    autoload :ThinWebsocketConnection, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/thin_websocket_connection')

    autoload :Mongrel2Puppet, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/mongrel2_puppet')

    # auxilliary services
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

    class << self
      def require_thin
        unless defined?(::Rack)
          # let's load rack
          gem 'rack', '>= 1.1.0'
          require 'rack'
        end

        unless defined?(::Thin)
          # let's load thin
          gem 'thin', '>= 1.2.7'
          require 'thin'
        end
      end

      def require_redis
        unless defined?(::Redis)
          gem 'redis', '>= 2.0.0'
          require 'redis'
        end
      end
    end

  end
end
