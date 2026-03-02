# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      class String < Value
        # Performance-optimized cast with short-circuit for already-correct types
        def self.cast(value, options = {})
          return nil if value.nil?
          # Short-circuit: return immediately if already a String with no options
          # Use identity check for EMPTY_OPTIONS (faster than .empty?)
          if value.is_a?(::String) && options.equal?(EMPTY_OPTIONS)
            return value
          end

          value = value.to_s
          Model::Services::Type::Validator::String.validate!(value, options) unless options.equal?(EMPTY_OPTIONS)
          value
        end

        # xs:string format
        def to_xml
          value&.to_s
        end

        # JSON string
        def to_json(*_args)
          value
        end

        # YAML string
        def to_yaml
          value
        end

        # TOML string
        def to_toml
          value&.to_s
        end

        def self.from_xml(value)
          cast(value)
        end

        def self.from_json(value)
          cast(value)
        end

        def self.from_yaml(value)
          cast(value)
        end

        def self.from_toml(value)
          cast(value)
        end

        # Default XSD type for String
        #
        # @return [String] xs:string
        def self.default_xsd_type
          "xs:string"
        end
      end
    end
  end
end
