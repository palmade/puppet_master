module Palmade::PuppetMaster
  # a set of different puppets
  class Family
    DEFAULT_OPTIONS = { }

    autoload :StandardPuppets, File.join(File.dirname(__FILE__), 'family/standard_puppets')

    attr_reader :puppets
    attr_reader :logger

    def initialize(options = { })
      @options = DEFAULT_OPTIONS.merge(options)
      @puppets = { }
    end

    def main_puppet
      @puppets[nil]
    end

    def [](k)
      puppets[k]
    end

    def []=(k, v)
      puppets[k] = v
    end

    def build!(m)
      unless m.logger.nil?
        @logger = m.logger
      end

      @puppets.each do |k, p|
        p.build!(m, self)
      end

      @puppets.each do |k, p|
        p.post_build(m, self)
      end
    end

    def murder_lazy_workers!(m)
      @puppets.each do |k, p|
        p.murder_lazy_workers!(m, self)
      end
    end

    def maintain_workers!(m)
      @puppets.each do |k, p|
        p.maintain_workers!(m, self)
      end
    end

    def kill_each_workers(m, signal)
      @puppets.each do |k, p|
        p.kill_each_workers(m, self, signal)
      end
    end

    def worker_count
      count = 0
      @puppets.each do |k, p|
        count += p.workers.size
      end
      count
    end

    def all_workers_dead?(m)
      worker_count == 0
    end

    def resign!(m, worker)
      @puppets.each do |k, p|
        p.resign!(m, self, worker)
      end
    end

    def reap!(m, wpid, status)
      @puppets.each do |k, p|
        p.reap!(m, self, wpid, status)
      end
    end

    include StandardPuppets
  end
end
