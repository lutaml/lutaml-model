module Lutaml
  module Model
    module Type
      class Float < Value
        def self.cast(value, options = {})
          return nil if value.nil?

          Model::Services::Type::Validator::Number.validate!(value, options)
          value.to_f
        end

        def self.serialize(value)
          return nil if value.nil?

          cast(value)
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

        # XSD type for Float
        #
        # @return [String] xs:float
        def self.xsd_type
          "xs:float"
        end
      end
    end
  end
end
