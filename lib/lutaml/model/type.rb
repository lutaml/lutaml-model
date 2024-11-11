# lib/lutaml/model/type.rb
require "date"
require "bigdecimal"

module Lutaml
  module Model
    module Type
      class << self
        def register(type_name, type_class)
          unless type_class < Value
            raise TypeError,
                  "class '#{type_class}' is not a valid Lutaml::Model::Type::Value"
          end

          @registry ||= {}
          @registry[type_name.to_sym] = type_class
        end

        def lookup(type_name)
          @registry ||= {}
          klass = @registry[type_name.to_sym]
          raise UnknownTypeError.new(type_name) unless klass

          klass
        end

        def cast(value, type)
          return nil if value.nil?

          type.cast(value)
        end

        def serialize(value, type)
          return nil if value.nil?

          type.serialize(value)
        end
      end

      # Base Value class for all types
      class Value
        def self.cast(value)
          return nil if value.nil?

          value.to_s
        end

        def self.serialize(value)
          return nil if value.nil?

          value.to_s
        end
      end
    end
  end
end

# Register built-in types
require_relative "type/string"
require_relative "type/integer"
require_relative "type/float"
require_relative "type/date"
require_relative "type/time"
require_relative "type/date_time"
require_relative "type/time_without_date"
require_relative "type/boolean"
require_relative "type/decimal"
require_relative "type/hash"
