module Lutaml
  module Model
    module Type
      class Symbol < Value
        def self.cast(value, _options = {})
          return nil if value.nil?
          return value if value.is_a?(::Symbol)
          return nil if uninitialized_value?(value)

          cast_string_to_symbol(value.to_s)
        end

        def self.serialize(value)
          return nil if value.nil?

          cast(value)
        end

        def self.uninitialized_value?(value)
          value.respond_to?(:uninitialized?) && value.uninitialized?
        end

        def self.cast_string_to_symbol(value)
          return nil if value.empty?

          match = value.match(/^:(.+):$/)

          if match && match[1]
            match[1].to_sym
          else
            value.to_sym
          end
        end

        private_class_method :uninitialized_value?, :cast_string_to_symbol # Format-specific serialization methods

        def to_xml
          # For XML, we use the :symbol: format to distinguish from strings
          ":#{value}:"
        end

        def to_json(*_args)
          # For JSON, we use the :symbol: format since JSON doesn't support symbols
          ":#{value}:"
        end

        def to_yaml
          # YAML natively supports symbols, so return the actual symbol
          value
        end

        def to_toml
          # For TOML, we use the :symbol: format since TOML doesn't support symbols
          ":#{value}:"
        end

        def self.from_xml(value)
          cast(value)
        end

        def self.from_json(value)
          cast(value)
        end

        def self.from_yaml(value)
          # YAML can already contain actual symbols or strings
          cast(value)
        end

        def self.from_toml(value)
          cast(value)
        end

        # Override to_s to return the symbol as a string without quotes
        def to_s
          value.to_s
        end
      end
    end
  end
end
