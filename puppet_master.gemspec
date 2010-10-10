# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{puppet_master}
  s.version = "0.1"

  s.required_rubygems_version = Gem::Requirement.new(">= 1.2") if s.respond_to? :required_rubygems_version=
  s.authors = ["markjeee"]
  s.date = %q{2010-10-10}
  s.description = %q{Master of puppets}
  s.email = %q{}
  s.extra_rdoc_files = ["README", "lib/palmade/puppet_master.rb", "lib/palmade/puppet_master/asinc_puppet.rb", "lib/palmade/puppet_master/config.rb", "lib/palmade/puppet_master/configurator.rb", "lib/palmade/puppet_master/controller.rb", "lib/palmade/puppet_master/eventd_puppet.rb", "lib/palmade/puppet_master/family.rb", "lib/palmade/puppet_master/family/standard_puppets.rb", "lib/palmade/puppet_master/master.rb", "lib/palmade/puppet_master/proxy_puppet.rb", "lib/palmade/puppet_master/puppet.rb", "lib/palmade/puppet_master/runner.rb", "lib/palmade/puppet_master/service.rb", "lib/palmade/puppet_master/service_cache.rb", "lib/palmade/puppet_master/service_queue.rb", "lib/palmade/puppet_master/service_redis.rb", "lib/palmade/puppet_master/service_tokyo_cabinet.rb", "lib/palmade/puppet_master/socket_helper.rb", "lib/palmade/puppet_master/thin_backend.rb", "lib/palmade/puppet_master/thin_connection.rb", "lib/palmade/puppet_master/thin_puppet.rb", "lib/palmade/puppet_master/thin_websocket_connection.rb", "lib/palmade/puppet_master/utils.rb", "lib/palmade/puppet_master/worker.rb", "lib/palmade/puppet_master/workling_puppet.rb"]
  s.files = ["CHANGELOG", "Manifest", "README", "Rakefile", "lib/palmade/puppet_master.rb", "lib/palmade/puppet_master/asinc_puppet.rb", "lib/palmade/puppet_master/config.rb", "lib/palmade/puppet_master/configurator.rb", "lib/palmade/puppet_master/controller.rb", "lib/palmade/puppet_master/eventd_puppet.rb", "lib/palmade/puppet_master/family.rb", "lib/palmade/puppet_master/family/standard_puppets.rb", "lib/palmade/puppet_master/master.rb", "lib/palmade/puppet_master/proxy_puppet.rb", "lib/palmade/puppet_master/puppet.rb", "lib/palmade/puppet_master/runner.rb", "lib/palmade/puppet_master/service.rb", "lib/palmade/puppet_master/service_cache.rb", "lib/palmade/puppet_master/service_queue.rb", "lib/palmade/puppet_master/service_redis.rb", "lib/palmade/puppet_master/service_tokyo_cabinet.rb", "lib/palmade/puppet_master/socket_helper.rb", "lib/palmade/puppet_master/thin_backend.rb", "lib/palmade/puppet_master/thin_connection.rb", "lib/palmade/puppet_master/thin_puppet.rb", "lib/palmade/puppet_master/thin_websocket_connection.rb", "lib/palmade/puppet_master/utils.rb", "lib/palmade/puppet_master/worker.rb", "lib/palmade/puppet_master/workling_puppet.rb", "test/test_helper.rb", "test/thin_websocket_test.rb", "puppet_master.gemspec"]
  s.homepage = %q{}
  s.rdoc_options = ["--line-numbers", "--inline-source", "--title", "Puppet_master", "--main", "README"]
  s.require_paths = ["lib"]
  s.rubyforge_project = %q{palmade}
  s.rubygems_version = %q{1.3.7}
  s.summary = %q{Master of puppets}
  s.test_files = ["test/test_helper.rb", "test/thin_websocket_test.rb"]

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
    else
    end
  else
  end
end
