module Lutaml
  module Model
    class ValueTransformer
      attr_reader :value

      def initialize(value = nil)
        @value = value
      end

      def self.from(value, format)
        new.send(:"from_#{format}", value)
      end

      def self.to(value, format)
        new(value).send(:"to_#{format}")
      end

      def self.can_transform?(method, format)
        method_defined?(:"#{method}_#{format}", false)
      end
    end
  end
end
