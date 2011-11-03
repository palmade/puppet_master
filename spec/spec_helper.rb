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

RSpec.configure do |config|
  config.before(:each) do
    Logger.stub(:new) { logger }
  end
end
