module Palmade::PuppetMaster
  class WorklingPuppet < Palmade::PuppetMaster::EventdPuppet
    DEFAULT_OPTIONS = {
      :worklings => :all,
      :routing => nil,
      :dispatcher => nil,
      :nap_time => 0.5
    }

    attr_reader :worklings

    def initialize(options = { }, &block)
      super(DEFAULT_OPTIONS.merge(options), &block)

      if @proc_tag.nil?
        @proc_tag = "workling"
      else
        @proc_tag = "#{@proc_tag}.workling"
      end

      @worklings = @options[:worklings]
      @discovered_classes = nil
      @active_routes = nil

      @dispatcher = nil
      @routng = nil
    end

    def post_build(m, fam)
      super

      # this is on post-build, since if we're running with thin
      # we want thin to load rails adapter first
      if @options[:dispatcher].nil?
        @dispatcher = Workling::Remote.dispatcher
      else
        @dispatcher = @options[:dispatcher]
      end

      if @options[:routing].nil?
        @routing = @dispatcher.routing
      else
        @routing = @options[:routing]
      end
    end

    def client
      @dispatcher.client
    end

    def work_loop(worker, &block)
      super(worker) do
        if block_given?
          yield(self, worker)
        elsif !@work_loop.nil?
          @work_loop.call(self, worker)
        end

        EventMachine.next_tick { work_routes(worker) }
      end
    end

    protected

    def work_routes(w)
      return unless w.ok?
      w.alive!

      active_routes.each do |ar|
        args = client.retrieve(ar)
        unless args.nil?
          run(ar, args)
        end
      end unless active_routes.nil? || active_routes.empty?

      if w.ok?
        w.alive!
        EventMachine.add_timer(@options[:nap_time]) { work_routes(w) }
      else
        # do nothing, let's just let it drop
      end
    end

    def run(route, args)
      klass = @routing[route]
      method = @routing.method_name(route)

      #warn "dispatching: #{klass} #{method}, #{args.inspect}"
      klass.dispatch_to_worker_method(method, *args)
    end

    def discovered_classes
      if @discovered_classes.nil?
        if @worklings == :all
          @discovered_classes = Workling::Discovery.discovered.dup
        else
          @discovered_classes = [ ]
          @worklings.each do |cn|
            if Workling::Discovery.discovered.include?(cn)
              @discovered_classes.push(cn)
            end
          end
        end
        @discovered_classes
      else
        @discovered_classes
      end
    end

    def active_routes
      if @active_routes.nil?
        @active_routes = discovered_classes.map { |clazz| @routing.queue_names_routing_class(clazz) }.flatten
      else
        @active_routes
      end
    end
  end
end
