module Lutaml
  module Model
    module Type
      class String < Value
        def self.cast(value)
          return nil if value.nil?

          validate_pattern!(value) if pattern_available?
          Model::Services::Type::Validator.validate_values!(value, values) if values_available?
          value.to_s
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

        def self.values_available?
          Utils.present?(values)
        end

        def self.values
          @values
        end

        def self.pattern_available?
          Utils.present?(pattern)
        end

        def self.pattern
          @pattern
        end

        def self.validate_pattern!(value)
          raise Lutaml::Model::Type::PatternNotMatchedError.new(value, pattern) unless value.match?(pattern)
        end
      end
    end
  end
end
