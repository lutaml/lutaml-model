# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      class Symbol < Value
        def self.cast(value, options = {})
          return nil if value.nil?
          return value if Utils.uninitialized?(value)
          return nil if value.respond_to?(:empty?) && value.empty?

          # Convert to string for validation and unwrapping
          str_value = if value.is_a?(::Symbol)
                        # Already a symbol, convert to string for validation
                        value.to_s
                      elsif value.is_a?(::String)
                        # Unwrap if needed, then validate
                        unwrap_symbol_string(value)
                      else
                        # Other types - convert to string
                        value.to_s
                      end

          # Use identity check for EMPTY_OPTIONS (faster than .empty?)
          unless options.equal?(EMPTY_OPTIONS)
            Model::Services::Type::Validator::Symbol.validate!(str_value,
                                                               options)
          end

          # Convert to symbol after validation passes
          str_value.to_sym
        end

        def self.serialize(value)
          return nil if value.nil?
          return value if Utils.uninitialized?(value)

          # If it's already a symbol, return it
          return value if value.is_a?(::Symbol)

          # If it's a string, convert and unwrap if needed
          if value.is_a?(::String)
            return unwrap_symbol_string(value).to_sym
          end

          # For other types, convert to symbol
          value.to_sym
        end

        # XSD type for Symbol
        #
        # Symbols are serialized as strings in XSD
        # @return [String] xs:string
        def self.default_xsd_type
          "xs:string"
        end

        def self.unwrap_symbol_string(value)
          match = value.match(/^:(.+):$/)
          match && match[1] ? match[1] : value
        end

        private_class_method :unwrap_symbol_string

      end
    end
  end
end
