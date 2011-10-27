module Palmade::PuppetMaster
  class Family
    DEFAULT_OPTIONS = { }

    autoload :StandardPuppets, File.join(File.dirname(__FILE__), 'family/standard_puppets')

    attr_reader :puppets
    attr_reader :logger

    def initialize(master, options = { })
      @options = DEFAULT_OPTIONS.merge(options)
      @puppets = { }
      @master  = master
    end

    def main_puppet
      @puppets[nil]
    end

    def [](k)
      puppets[k]
    end

    def []=(k, v)
      v.master ||= @master
      v.family ||= self
      puppets[k] = v
    end

    def build!(master = @master, family = self)
      unless @master.logger.nil?
        @logger = @master.logger
      end

      @puppets.each do |k, p|
        if p.method(:build!).arity == 2
          warn "[DEPRECATION] `master` and `family` should be passed on initialization"
          p.build!(master, family)
        else
          p.build!
        end
      end

      @puppets.each do |k, p|
        p.post_build
      end
    end

    def murder_lazy_workers!
      @puppets.each do |k, p|
        p.murder_lazy_workers!
      end
    end

    def maintain_workers!
      @puppets.each do |k, p|
        p.maintain_workers!
      end
    end

    def spawn_missing_workers
      @puppets.each do |k, p|
        p.spawn_missing_workers
      end
    end

    def kill_each_workers(signal)
      @puppets.each do |k, p|
        p.kill_each_workers(signal)
      end
    end

    def worker_count
      count = 0
      @puppets.each do |k, p|
        count += p.workers.size
      end
      count
    end

    def all_workers_dead?
      worker_count == 0
    end

    def resign!(worker)
      @puppets.each do |k, p|
        p.resign!(worker)
      end
    end

    def reap!(wpid, status)
      @puppets.each do |k, p|
        p.reap!(wpid, status)
      end
    end

    include StandardPuppets
  end
end
