module Lutaml
  module Model
    module Type
      class Symbol < Value
        def self.cast(value, options = {})
          return nil if value.nil?
          return nil if value.is_a?(Lutaml::Model::UninitializedClass)
          return nil if value.respond_to?(:empty?) && value.empty?

          # Convert to string for validation and unwrapping
          if value.is_a?(::Symbol)
            # Already a symbol, convert to string for validation
            str_value = value.to_s
          elsif value.is_a?(::String)
            # Unwrap if needed, then validate
            str_value = unwrap_symbol_string(value)
          else
            # Other types - convert to string
            str_value = value.to_s
          end

          # Validate the string representation
          Model::Services::Type::Validator::Symbol.validate!(str_value, options)

          # Convert to symbol after validation passes
          str_value.to_sym
        end

        def self.serialize(value)
          return nil if value.nil?
          return nil if value.is_a?(Lutaml::Model::UninitializedClass)

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
        def self.xsd_type
          "xs:string"
        end

        def self.unwrap_symbol_string(value)
          match = value.match(/^:(.+):$/)
          match && match[1] ? match[1] : value
        end

        private_class_method :unwrap_symbol_string

        def to_xml
          # For XML, we use the :symbol: format to distinguish from strings
          ":#{value}:"
        end

        def to_json(*_args)
          # For JSON, we use the :symbol: format since JSON doesn't support symbols
          ":#{value}:"
        end

        def to_toml
          # For TOML, we use the :symbol: format since TOML doesn't support symbols
          ":#{value}:"
        end
      end
    end
  end
end
