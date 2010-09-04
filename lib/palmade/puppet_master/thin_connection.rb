module Palmade::PuppetMaster
  class ThinConnection < Thin::Connection
    attr_accessor :puppet
    attr_accessor :worker

    def post_init
      @working = false
      super
    end

    def receive_data(data)
      @working = true
      super(data)
    end

    def working?
      @working ||= false
    end

    def terminate_request
      @working = false
      super
    end

    def cant_persist!
      @can_persist = false
    end

    def post_process(result)
      super
      puppet.post_process(self, worker) unless puppet.nil?
    end
  end
end
