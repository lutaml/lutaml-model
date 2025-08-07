module Lutaml
  module Model
    class KeyValueDocument
      attr_reader :attributes, :__register

      def initialize(attributes = {}, register: nil)
        @attributes = attributes
        @__register = register || Lutaml::Model::Config.default_register
      end

      def [](key)
        @attributes[key]
      end

      def []=(key, value)
        @attributes[key] = value
      end

      def key?(key)
        @attributes.key?(key)
      end

      def to_h
        @attributes
      end
    end
  end
end
