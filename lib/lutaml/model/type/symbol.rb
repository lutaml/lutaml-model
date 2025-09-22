module Lutaml
  module Model
    module Type
      class Symbol < Value
        def self.cast(value, options = {})
          return nil if Utils.blank?(value)
          return value if Utils.uninitialized?(value)

          value = cast_string_to_symbol(value.to_s) unless value.is_a?(::Symbol)
          Model::Services::Type::Validator::Symbol.validate!(value, options)

          value
        end

        def self.serialize(value)
          return nil if value.nil?

          cast(value)
        end

        def self.cast_string_to_symbol(value)
          match = value.match(/^:(.+):$/)
          value = match[1] if match && match[1]
          value.to_sym
        end

        private_class_method :cast_string_to_symbol # Format-specific serialization methods

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
