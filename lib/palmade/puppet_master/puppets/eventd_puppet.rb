module Palmade::PuppetMaster
  module Puppets
    class EventdPuppet < Base
      def work_loop(worker, ret = nil, &block)
        master_logger.warn "eventd worker #{worker.proc_tag} started: #{$$}"

        # trap(:USR1) {  } do nothing, it should reload logs
        [ :INT ].each { |sig| trap(sig) { } } # do nothing
        [ :QUIT ].each { |sig| trap(sig) { stop_work_loop(worker) } } # graceful shutdown
        [ :TERM, :KILL ].each { |sig| trap(sig) { exit!(0) } } # instant #shutdown

        EventMachine.epoll
        EventMachine.kqueue

        EventMachine.run do
          EventMachine.next_tick { first_tick }
          # do some work
          unless workloop_disabled?
            if block_given?
              yield(self, worker)
            elsif !@work_loop.nil?
              @work_loop.call(self, worker)
            else
              EventMachine.next_tick { work_work(worker) }
            end
          end
        end
        worker.stop!

        master_logger.warn "eventd worker #{worker.proc_tag} stopped: #{$$}"

        ret
      end

      def stop_work_loop(worker)
        EM.next_tick do
          worker.stop!
          EventMachine.stop
        end
      end

      def workloop_disabled?
        @options[:disable_workloop]
      end

      def first_tick
        #do nothing
      end
      protected

      def work_work(w)
        if !w.ok?
          stop_work_loop(w)
        else
          w.alive!
          perform_work(w)

          if w.ok?
            w.alive!
            EventMachine.add_timer(@options[:nap_time]) { work_work(w) }
          end
        end
      end

      def perform_work(w)
        raise NotImplementedError, "perform_work() not implemented for #{self.class.name}"
      end
    end
  end
end
