module Sources
  module Registry
    UnknownAdapter = Class.new(StandardError)

    class << self
      def register(klass)
        adapters[klass.key] = klass
      end

      def fetch(key)
        adapters.fetch(key.to_s) do
          raise UnknownAdapter, "no source adapter registered for #{key.inspect} (known: #{keys.join(', ')})"
        end
      end

      def keys = adapters.keys

      def reset! = @adapters = {}

      def load_defaults!
        reset!
        register(HackerNewsWhoIsHiring)
      end

      private
        def adapters = (@adapters ||= {})
    end
  end
end
