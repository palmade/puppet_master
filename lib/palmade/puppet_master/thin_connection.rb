module Palmade::PuppetMaster
  class ThinConnection < Thin::Connection
    attr_accessor :puppet
    attr_accessor :worker

    def post_process(result)
      super
      puppet.post_process(self, worker) unless puppet.nil?
    end
  end
end
