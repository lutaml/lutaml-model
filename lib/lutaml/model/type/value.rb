# frozen_string_literal: true

module Lutaml
  module Model
    # Isolated holder for format_type_serializer_for's memo: Type::Value
    # can be frozen by suites, which would freeze an ivar Hash with it.
    SERIALIZER_LOOKUP_CACHE = ::Class.new do
      class << self
        def cache
          @cache ||= {}
        end
      end
    end.cache

    module Type
      # Base class for all value types
      class Value
        prepend UninitializedClassGuard

        # Performance optimization: reusable empty options hash
        # Use options.equal?(EMPTY_OPTIONS) for fast-path checks
        EMPTY_OPTIONS = {}.freeze

        # Format type serializer registry
        # Keys: [format, TypeClass] => { to: Proc, from: Proc }
        @format_type_serializers = {}

        class << self
          # Register a custom type serializer for a specific format and type class.
          # Format plugins call this at load time to register their custom serialization logic.
          #
          # @param format [Symbol] the format (e.g., :xml, :json)
          # @param type_class [Class] the type class (must be <= Value)
          # @param to [Proc, nil] custom instance serialization proc (receives the type instance)
          # @param from [Proc, nil] custom class deserialization proc (receives the raw value)
          def register_format_type_serializer(format, type_class, to: nil,
from: nil)
            @format_type_serializers[[format, type_class]] =
              { to: to, from: from }.compact
          end

          # Look up a format type serializer, walking the class hierarchy.
          #
          # @param format [Symbol] the format
          # @param type_class [Class] the type class to look up
          # @return [Hash, nil] { to: Proc, from: Proc } or nil
          def format_type_serializer_for(format, type_class)
            # Hot path: memoize per [format, resolved class] — the hierarchy
            # walk below only runs on a miss. Format serializers register at
            # load time, so a hit is stable.
            cache = SERIALIZER_LOOKUP_CACHE
            key = [format, type_class]
            return cache[key] if cache.key?(key)

            klass = type_class
            found = nil
            while klass && klass <= Value
              s = @format_type_serializers[[format, klass]]
              if s
                found = s
                break
              end

              klass = klass.superclass
            end
            cache[key] = found
            found
          end
        end

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

        # Called from FormatRegistry when a new format is registered.
        # Defines to_{format} and from_{format} methods that check the
        # serializer registry first, falling back to default behavior.
        def self.register_format_to_from_methods(format)
          define_method(:"to_#{format}") do
            s = Value.format_type_serializer_for(format, self.class)
            s&.dig(:to) ? s[:to].call(self) : value
          end

          define_singleton_method(:"from_#{format}") do |v|
            s = Value.format_type_serializer_for(format, self)
            s&.dig(:from) ? s[:from].call(v) : cast(v)
          end
        end
      end
    end
  end
end
