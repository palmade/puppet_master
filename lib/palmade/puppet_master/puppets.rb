module Palmade::PuppetMaster
  # types of puppets
  module Puppets
    autoload :Base, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/puppets/base')
    autoload :EventdPuppet, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/puppets/eventd_puppet')
    autoload :Mongrel2Puppet, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/puppets/mongrel2_puppet')
    autoload :ThinPuppet, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/puppets/thin_puppet')

    module Thin
      autoload :Backend, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/puppets/thin/backend')
      autoload :Connection, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/puppets/thin/connection')
      autoload :WebsocketConnection, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/puppets/thin/websocket_connection')
    end

    module Mongrel2
      autoload :Backend, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/puppets/mongrel2/backend')
      autoload :Connection, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/puppets/mongrel2/connection')
      autoload :Request, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/puppets/mongrel2/request')
      autoload :Response, File.join(PUPPET_MASTER_LIB_DIR, 'puppet_master/puppets/mongrel2/response')
    end
  end
end
