module Palmade::PuppetMaster
  class Worker
    attr_accessor :nr
    attr_accessor :tmp
    attr_accessor :master_pid

    attr_reader :logger
    attr_reader :stopped
    alias :stopped? :stopped

    attr_reader :master
    attr_reader :data

    def initialize(m, p, nr)
      @tmp = Palmade::PuppetMaster::Utils.tmpio
      @master = m
      @puppet = p
      @data = { }
      @logger = @master.logger

      @nr = nr
      @master_pid = m.pid
      @m = 0
      @stopped = false
      @initialized_time = @tmp.stat.ctime
    end

    def services
      @master.services
    end

    # worker objects may be compared to just plain numbers
    def ==(other_nr)
      if other_nr.is_a?(Numeric)
        self.nr == other_nr
      else
        super(other_nr)
      end
    end

    def close
      @tmp.close rescue nil
    end

    def proc_tag
      if @puppet.proc_tag.nil?
        "#{@nr}"
      else
        "#{@puppet.proc_tag}.#{@nr}"
      end
    end

    def fork
      @puppet.before_fork(self)
      logger.warn "forking worker #{proc_tag}"
      Kernel.fork
    end

    def work
      @m = 0
      init

      ret = nil
      ret = @puppet.before_work(self, ret)
      ret = @puppet.work_loop(self, ret)
      ret = @puppet.after_work(self, ret)
      ret
    end

    def checked_in?
      @tmp.stat.ctime > @initialized_time
    end

    def ok?
      is_master_ok? && !@stopped
    end

    def is_master_ok?
      @master_pid == Process.ppid
    end

    def alive!
      # 1.8.x's ctime only has a precision of up to a second and we need a
      # precision of up to a nanosecond. We sleep for 1 second to
      # compensate. This is only needed for the first notification.
      #
      # Succeeding notifications don't matter since the timeout would be at
      # least a second.
      if !checked_in? && RUBY_VERSION =~ /^1\.8/
        sleep 1
      end

      @tmp.chmod(@m = 0 == @m ? 1 : 0)
    end

    def stop!
      @stopped = true
    end

    # initialize the new fork!
    def init
      @master.reopen_logger
      @master.detach_listeners_from_master
      @master.reset_services
      @master.resign!(self)
      @master.reset_application!(self)

      @tmp.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC)

      @puppet.after_fork(self)
    end
  end
end
