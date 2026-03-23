# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      # Base class for all value types
      class Value
        prepend UninitializedClassGuard

        include Lutaml::Xml::Type::Configurable

        # Performance optimization: reusable empty options hash
        # Use options.equal?(EMPTY_OPTIONS) for fast-path checks
        EMPTY_OPTIONS = {}.freeze

        attr_reader :value

        def initialize(value)
          @value = self.class.cast(value)
        end

        def initialized?
          true
        end

        def self.cast(value, _options = {})
          return nil if value.nil?
          return value if Utils.uninitialized?(value)

          value
        end

        def self.serialize(value)
          return nil if value.nil?
          return value if Utils.uninitialized?(value)

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
