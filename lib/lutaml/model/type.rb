module Lutaml
  module Model
    module Type
      TYPE_CODES = {
        string: "Lutaml::Model::Type::String",
        integer: "Lutaml::Model::Type::Integer",
        float: "Lutaml::Model::Type::Float",
        double: "Lutaml::Model::Type::Float",
        decimal: "Lutaml::Model::Type::Decimal",
        date: "Lutaml::Model::Type::Date",
        time: "Lutaml::Model::Type::Time",
        date_time: "Lutaml::Model::Type::DateTime",
        time_without_date: "Lutaml::Model::Type::TimeWithoutDate",
        boolean: "Lutaml::Model::Type::Boolean",
        reference: "Lutaml::Model::Type::Reference",
        hash: "Lutaml::Model::Type::Hash",
        symbol: "Lutaml::Model::Type::Symbol",
        duration: "Lutaml::Model::Type::Duration",
        uri: "Lutaml::Model::Type::Uri",
        qname: "Lutaml::Model::Type::QName",
        base64_binary: "Lutaml::Model::Type::Base64Binary",
        hex_binary: "Lutaml::Model::Type::HexBinary",
      }.freeze

      class << self
        # Register all built-in types into any TypeRegistry.
        #
        # This method is used by the new type resolution architecture.
        # It does NOT depend on the Type module's internal @registry.
        #
        # @param registry [TypeRegistry] The registry to populate
        # @return [void]
        #
        # @example
        #   registry = TypeRegistry.new
        #   Type.register_builtin_types_in(registry)
        #   registry.lookup(:string)  #=> Lutaml::Model::Type::String
        def register_builtin_types_in(registry)
          TYPE_CODES.each do |type_name, type_class_name|
            # Resolve the class constant directly (not via @registry)
            type_class = const_get(type_class_name)
            registry.register(type_name, type_class)
          end
        end

        # Legacy: Register built-in types into Type module's internal registry.
        #
        # @deprecated Use {register_builtin_types_in} instead
        # @return [void]
        def register_builtin_types
          TYPE_CODES.each do |type_name, type_class|
            register(type_name, const_get(type_class))
          end
        end

        # Register a type in the Type module's internal registry.
        #
        # @param type_name [Symbol, String] The type name
        # @param type_class [Class] The type class (must inherit from Value)
        # @return [void]
        # @raise [TypeError] If type_class is not a valid type class
        def register(type_name, type_class)
          unless type_class < Value
            raise TypeError,
                  "class '#{type_class}' is not a valid Lutaml::Model::Type::Value"
          end

          @registry ||= {}
          @registry[type_name.to_sym] = type_class
        end

        # Look up a type class by name.
        #
        # @param type_name [Symbol, String, Class] The type name or class
        # @return [Class] The type class
        # @raise [UnknownTypeError] If type is not found
        def lookup(type_name)
          return type_name if type_name.is_a?(Class)

          @registry ||= {}
          klass = @registry[type_name.to_sym]

          raise UnknownTypeError.new(type_name) unless klass

          klass
        end

        # Look up a type class by name, returning nil if not found.
        # Used by TypeResolver for backward compatibility fallback.
        #
        # @param type_name [Symbol, String, Class] The type name or class
        # @return [Class, nil] The type class or nil if not found
        def lookup_ignoring_fallback(type_name)
          return type_name if type_name.is_a?(Class)

          @registry ||= {}
          @registry[type_name.to_sym]
        end

        # Cast a value to the specified type.
        #
        # @param value [Object] The value to cast
        # @param type [Symbol, String, Class] The target type
        # @return [Object] The cast value
        def cast(value, type)
          return nil if value.nil?

          lookup(type).cast(value)
        end

        # Serialize a value using the specified type.
        #
        # @param value [Object] The value to serialize
        # @param type [Symbol, String, Class] The type
        # @return [Object] The serialized value
        def serialize(value, type)
          return nil if value.nil?

          lookup(type).serialize(value)
        end
      end
    end
  end
end

# Load type classes
require_relative "type/value"
require_relative "type/string"
require_relative "type/integer"
require_relative "type/float"
require_relative "type/date"
require_relative "type/time"
require_relative "type/date_time"
require_relative "type/time_without_date"
require_relative "type/boolean"
require_relative "type/decimal"
require_relative "type/reference"
require_relative "type/hash"
require_relative "type/symbol"
require_relative "type/duration"
require_relative "type/uri"
require_relative "type/qname"
require_relative "type/base64_binary"
require_relative "type/hex_binary"

# Register built-in types in Type module's internal registry
# (for backward compatibility)
Lutaml::Model::Type.register_builtin_types
