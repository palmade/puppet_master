module Palmade::PuppetMaster
  class Worker
    attr_accessor :nr
    attr_accessor :tmp
    attr_accessor :master_pid

    attr_reader :logger
    attr_reader :stopped
    alias :stopped? :stopped

    attr_reader :master

    def initialize(m, p, nr)
      @tmp = Palmade::PuppetMaster::Utils.tmpio
      @master = m
      @puppet = p
      @logger = @master.logger

      @nr = nr
      @master_pid = m.master_pid
      @m = 0
      @stopped = false
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
      @puppet.work_loop(self)
    end

    def ok?
      is_master_ok? && !@stopped
    end

    def is_master_ok?
      @master_pid == Process.ppid
    end

    def alive!
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

    def init_self_pipe!
      #SELF_PIPE.each { |io| io.close rescue nil }
      #SELF_PIPE.replace(IO.pipe)
      #SELF_PIPE.each { |io| io.fcntl(Fcntl::F_SETFD, Fcntl::FD_CLOEXEC) }
    end
  end
end
