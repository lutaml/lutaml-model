require_relative "../config"

module Lutaml
  module Model
    module Type
      # Base class for all value types
      class Value
        attr_reader :value

        def initialize(value)
          @value = self.class.cast(value)
        end

        def initialized?
          true
        end

        def self.cast(value)
          return nil if value.nil?

          value
        end

        def self.serialize(value)
          return nil if value.nil?

          new(value).to_s
        end

        # Instance methods for serialization
        def to_s
          value.to_s
        end

        # Class-level format conversion
        def self.from_format(value, format)
          new(send(:"from_#{format}", value))
        end

        # called from config when a new format is added
        def self.register_format_to_from_methods(format)
          define_method(:"to_#{format}") do
            value
          end

          define_singleton_method(:"from_#{format}") do |value|
            cast(value)
          end
        end
      end
    end
  end
end
