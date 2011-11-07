# This is the default configurator that PuppetMaster will call
# so you can use it to determine which environment
# configurator you want to load
main do |m, config, controller|
  if config[:environment].nil?
    config[:environment] = config[:daemonize] ? 'production' : 'development'
  end

  call(config[:environment])
end

development do |m, config, controller|
  call :common
end

production do |m, config, controller|
  call :common

  unless config.include?(:servers)
    m.family.main_puppet.count = 6
  end
end

common do |m, config, controller|
  fam = m.single_family!

  if config.include?(:tag)
    proc_tag = "#{config[:tag]}.account.#{config[:environment]}"
  else
    proc_tag = "account.#{config[:environment]}"
  end

  if config.include?(:servers)
    count = config[:servers]
  else
    count = 1
  end

  Object.const_set('NEW_RELIC_APP_NAME', 'appctl')

  m.proc_tag = proc_tag
  fam.puppet(:proc_tag => proc_tag,
                  :adapter => :rails,
                  :adapter_options => config.symbolize_keys,
                  :count => count)
end
