module Lutaml
  module Model
    class Store
      class << self
        def instance
          @instance ||= new
        end

        def reset!
          @instance = new
        end

        def register(object)
          instance.register(object)
        end

        def resolve(model_class, reference_key, reference_value)
          instance.resolve(model_class, reference_key, reference_value)
        end

        def clear
          instance.clear
        end

        def store
          instance.store
        end
      end

      def initialize
        @store = ::Hash.new { |hash, key| hash[key] = [] }
      end

      def register(object)
        model_class = object.class.to_s

        @store[model_class] << object unless @store[model_class].include?(object)
      end

      def resolve(model_class, reference_key, reference_value)
        return nil unless @store[model_class.to_s]

        @store[model_class.to_s].find { |obj| obj.send(reference_key) == reference_value }
      end

      def clear
        @store = ::Hash.new { |hash, key| hash[key] = [] }
      end

      def store
        @store
      end
    end
  end
end
