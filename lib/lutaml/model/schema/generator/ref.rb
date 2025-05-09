module Lutaml
  module Model
    module Schema
      module Generator
        # This class is used to generate a reference to a schema definition.
        # It is used in the context of generating JSON schemas.
        class Ref
          attr_reader :name

          def initialize(type)
            @type = type
            @name = @type.name.gsub("::", "_")
          end

          def to_schema
            {
              "$ref" => "#/$defs/#{name}",
            }
          end
        end
      end
    end
  end
end
