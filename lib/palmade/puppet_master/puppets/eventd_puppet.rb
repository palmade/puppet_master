module Palmade::PuppetMaster
  module Puppets
    class EventdPuppet < Base
      DEFAULT_OPTIONS = Palmade::PuppetMaster::Puppet::DEFAULT_OPTIONS.merge({ })

      def work_loop(worker, ret = nil, &block)
        master_logger.warn "eventd worker #{worker.proc_tag} started: #{$$}"

        # trap(:USR1) {  } do nothing, it should reload logs
        [ :INT ].each { |sig| trap(sig) { } } # do nothing
        [ :QUIT ].each { |sig| trap(sig) { stop_work_loop(worker) } } # graceful shutdown
        [ :TERM, :KILL ].each { |sig| trap(sig) { exit!(0) } } # instant #shutdown

        EventMachine.run do
          EventMachine.epoll rescue nil
          EventMachine.kqueue rescue nil

          # do some work
          if block_given?
            yield(self, worker)
          elsif !@work_loop.nil?
            @work_loop.call(self, worker)
          else
            EventMachine.next_tick { work_work(worker) }
          end
        end
        worker.stop!

        master_logger.warn "eventd worker #{worker.proc_tag} stopped: #{$$}"

        ret
      end

      def stop_work_loop(worker)
        worker.stop!
        EventMachine.stop_event_loop if EventMachine.reactor_running?
      end

      protected

      def work_work(w)
        return unless w.ok?
        w.alive!
        perform_work(w)
        if w.ok?
          w.alive!
          EventMachine.add_timer(@options[:nap_time]) { work_work(w) }
        end
      end

      def perform_work(w)
        raise NotImplementedError, "perform_work() not implemented for #{self.class.name}"
      end
    end
  end
end
