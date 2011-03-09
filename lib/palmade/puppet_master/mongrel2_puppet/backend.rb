require 'ffi-rzmq'

module Palmade::PuppetMaster
  class Mongrel2Puppet::Backend

    CTX = EM::ZeroMQ::Context.new(1)

    def initialize(app, options)
      @app = app
      @uuid, @sub, @pub = options['uuid'], options['recv'], options['send']
    end

    def start
      starter = proc do
        connect
      end

      if EventMachine.reactor_running?
        starter.call
      else
        EventMachine.run(&starter)
      end
    end

    def connect
      # Connect to send responses
      @resp = CTX.connect(ZMQ::PUB, @pub, :identity => @uuid)

      # Connect to receive requests
      @reqs = CTX.connect(ZMQ::PULL, @sub, Mongrel2Puppet::Connection.new(@app, @resp))
    end

    def stop
      disconnect
    end

    def disconnect
      @reqs.unbind if @reqs
      @resp.unbind if @resp
    end

  end
end
