module Lutaml
  module Model
    module Type
      class Float < Value
        def self.cast(value)
          return nil if value.nil?

          Model::Services::Type::Validator.validate_values!(value, values) if values_available?
          Model::Services::Type::Validator.validate_min_max_bounds!(value, min_max_bounds) if min_max_bounds_available?
          value.to_f
        end

        def self.serialize(value)
          return nil if value.nil?

          cast(value)
        end

        def self.values_available?
          Utils.present?(values)
        end

        def self.values
          @values
        end

        def self.min_max_bounds_available?
          Utils.present?(min_max_bounds)
        end

        def self.min_max_bounds
          @min_max_bounds || {}
        end

        # Instance methods for specific formats
        # xs:float format
        def to_xml
          value.to_s
        end

        def to_yaml
          value
        end

        def to_json(*_args)
          value
        end
      end
    end
  end
end
