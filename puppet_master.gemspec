# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)

Gem::Specification.new do |s|
  s.name        = 'puppet_master'
  s.version     = '0.3.1'
  s.authors     = ['Palmade']
  s.homepage    = 'http://github.com/palmade/puppet_master'
  s.summary     = 'Master of Puppets'
  s.description = 'Master of Puppets'

  s.files            = `git ls-files`.split("\n")
  s.test_files       = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.require_paths    = ['lib']
  s.extra_rdoc_files = ['README']
  s.rdoc_options     = ['--line-numbers', '--inline-source', '--title', 'puppet_master', '--main', 'README']

  s.add_development_dependency 'rspec'
  s.add_development_dependency 'simplecov'
  s.add_development_dependency 'cucumber'
  s.add_development_dependency 'aruba'
  s.add_development_dependency 'rake'
end

