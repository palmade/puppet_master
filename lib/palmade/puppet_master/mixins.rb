module Palmade::PuppetMaster
  module Mixins
    autoload :RackAddForwardedSupport, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/mixins/rack_add_forwarded_support')
    autoload :FrameworkAdapters, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/mixins/framework_adapters')
  end
end
