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
        instance_methods(false).include?(:"#{method}_#{format}")
      end
    end
  end
end
