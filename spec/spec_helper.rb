require 'rubygems'
require 'simplecov'
SimpleCov.start

require 'bundler/setup'
require 'tempfile'

require 'palmade/puppet_master'

log_dir = File.join(File.expand_path('..', __FILE__), 'logs')
Dir.mkdir(log_dir) unless Dir.exists? log_dir
log_file = File.join(log_dir, "test-#{$$}.log")
logger = Logger.new(log_file)

module Helpers
  def spec_root
    File.join(File.expand_path('..', __FILE__))
  end

  def tmp_dir
    File.join(spec_root, 'tmp')
  end

  def socket_dir
    File.join(tmp_dir, 'socks')
  end

  def pid_dir
    File.join(tmp_dir, 'pids')
  end
end

module Matchers
  class ValidateWithLint
    def matches?(request)
      @request = request
      Rack::Lint.new(proc{[200, {'Content-Type' => 'text/html', 'Content-Length' => '0'}, []]}).call(@request.env)
      true
    rescue Rack::Lint::LintError => e
      @message = e.message
      false
    end

    def failure_message(negation=nil)
      "should#{negation} validate with Rack Lint: #{@message}"
    end

    def negative_failure_message
      failure_message ' not'
    end
  end

  def validate_with_lint
    ValidateWithLint.new
  end
end

RSpec.configure do |config|
  config.before(:each) do
    Logger.stub(:new) { logger }
  end

  config.include Matchers
  config.include Helpers
end
