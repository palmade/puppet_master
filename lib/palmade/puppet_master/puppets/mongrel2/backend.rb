module Palmade::PuppetMaster
  module Puppets::Mongrel2
    class Backend

      CTX = EM::ZeroMQ::Context.new(1)

      def initialize(app, options)
        @app = app
        @uuid, @sub, @pub = options['uuid'], options['recv'], options['send']
        @chroot = options['chroot']
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
        @resp = CTX.socket(ZMQ::PUB)
        @resp.connect(@pub)
        @resp.setsockopt(ZMQ::IDENTITY, @uuid)

        # Connect to receive requests
        @reqs = CTX.socket(ZMQ::PULL, Connection.new(@app, @resp, @chroot))
        @reqs.connect(@sub)
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
end
