require 'bundler/gem_tasks'
require 'rspec/core/rake_task'
require 'cucumber/rake/task'

RSpec::Core::RakeTask.new('spec')

Cucumber::Rake::Task.new(:features)

namespace :features do
  Cucumber::Rake::Task.new("no-slow", "Don't run @slow features") do |t|
    t.cucumber_opts = "--tags ~@slow"
  end

  Cucumber::Rake::Task.new(:wip, "Only run @wip features") do |t|
    t.cucumber_opts = "--tags @wip"
  end
end
