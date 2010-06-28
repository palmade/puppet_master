module Palmade::PuppetMaster
  class AsincPuppet < Palmade::PuppetMaster::EventdPuppet
    DEFAULT_OPTIONS = {
      :nap_time => 0.5,
      :app => nil,
      :reloader => nil
    }

    def initialize(asinc_classes, options = { }, &block)
      super(DEFAULT_OPTIONS.merge(options), &block)

      if @proc_tag.nil?
        @proc_tag = "asinc"
      else
        @proc_tag = "#{proc_tag}.asinc"
      end

      @asinc_worker_module = options[:worker_module] || Palmade::Acts::AsincWorker
      @asinc_classes = asinc_classes
      @resolved_asinc_classes = [ ]

      @app = @options[:app]
      @reloader = @options[:reloader]
    end

    def post_build(m, fam)
      case @app
      when String
        @app = Palmade::Inflector.constantize(@app).new
      end

      case @reloader
      when String
        @reloader = Palmade::Inflector.constantize(@reloader).new
      end
    end

    def work_loop(worker, &block)
      super(worker) do
        if block_given?
          yield(self, worker)
        elsif !@work_loop.nil?
          @work_loop.call(self, worker)
        end
        EventMachine.next_tick { work_tubes(worker) }
      end
    end

    def after_fork(w)
      super

      if @asinc_worker_module.is_a?(String)
        @asinc_worker_module = Palmade::Inflector.constantize(@asinc_worker_module)
      end

      if @reloader.nil?
        _resolve_asinc_classes!
        _attach_worker_module!
        _prepare_asinc_classes!
      end
    end

    protected

    # TODO: Change this to work with asinc!
    def work_tubes(w)
      return unless w.ok?
      w.alive!

      total_worked = 0

      # if reloader, used, pre-load apps here
      unless @reloader.nil?
        _resolve_asinc_classes!
        _attach_worker_module!
        _prepare_asinc_classes!
      end

      # prepare_for dispatch
      _prepare_for_work!
      begin
        # let's do one work at a time
        @resolved_asinc_classes.each do |klass_data|
          worked, expired = klass_data[0].asinc_work(@app, nil, 1)

          # should only be working on only one method
          # per class (though, we won't sleep, just do a next_tick) -- see below
          if worked > 0
            total_worked += worked
            break
          end
        end
      ensure
        _cleanup_after_work!

        unless @reloader.nil?
          @resolved_asinc_classes.clear
          @reloader.call(self)
        end
      end

      if w.ok?
        w.alive!
        if total_worked > 0
          EventMachine.next_tick { work_tubes(w) }
        else
          # let's take a nap
          EventMachine.add_timer(@options[:nap_time]) { work_tubes(w) }
        end
      else
        # do nothing, let's just let it drop
      end
    end

    private

    def _prepare_for_work!; end

    def _cleanup_after_work!; end

    def _resolve_asinc_classes!
      (0...@asinc_classes.size).each do |i|
        case @asinc_classes[i]
        when String
          @resolved_asinc_classes[i] = [ Palmade::Inflector.constantize(@asinc_classes[i].to_s) ]
        when Array
          @resolved_asinc_classes[i] = [ Palmade::Inflector.constantize(@asinc_classes[i][0].to_s) ] + @asinc_classes[1..-1]
        when Class
          @resolved_asinc_classes[i] = [ @asinc_classes[i] ]
        else
          raise TypeError, "Expecting either a string or a class, not #{@asinc_classes[i].class.name}"
        end
      end unless @asinc_classes.empty?
    end

    def _attach_worker_module!
      (0...@resolved_asinc_classes.size).each do |i|
        unless @resolved_asinc_classes[i][0].included_modules.include?(@asinc_worker_module)
          @resolved_asinc_classes[i][0].send(:include, @asinc_worker_module)
        end
      end unless @resolved_asinc_classes.empty?
    end

    def _prepare_asinc_classes!
      (0...@resolved_asinc_classes.size).each do |i|
        klass = @resolved_asinc_classes[i][0]
        klass.send(:asinc_prepare, *@resolved_asinc_classes[i][1..-1]) if klass.respond_to?(:asinc_prepare)
      end unless @resolved_asinc_classes.empty?
    end
  end
end
