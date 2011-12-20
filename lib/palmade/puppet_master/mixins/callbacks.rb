module Palmade::PuppetMaster
  module Mixins
    module Callbacks
      attr_accessor :callbacks

      def run_callback_with_limit(hook, limit, *args)
        return unless @callbacks
        hook = hook.to_sym
        return unless @callbacks.include? hook

        limit ||= @callbacks[hook][:limit]
        return if limit > 0 and limit <= @callbacks[hook][:call_counter]

        @callbacks[hook][:callback].call *args
        @callbacks[hook][:call_counter] += 1
      end

      def run_callback(hook, *args)
        run_callback_with_limit(hook, nil, *args)
      end

      def run_callback_once(hook, *args)
        run_callback_with_limit(hook, 1, *args)
      end

      def on_callback(hook, limit = 0, &block)
        @callbacks ||= {}
        @callbacks[hook.to_sym] = {:callback => block,
                                   :limit => limit,
                                   :call_counter => 0}
      end

      def on_callback_once(hook, &block)
        on_callback(hook, 1, &block)
      end
    end
  end
end
