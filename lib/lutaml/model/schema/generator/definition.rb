require_relative "properties_collection"

module Lutaml
  module Model
    module Schema
      module Generator
        class Definition
          attr_reader :klass, :name

          def initialize(klass)
            @klass = klass
            @name = klass.name.gsub("::", "_")
          end

          def to_schema
            @schema = {
              name => {
                "type" => "object",
                "additionalProperties" => false,
                "properties" => properties_to_schema(klass),
              },
            }

            # Add choice validation if present
            if klass.choice_attributes.any?
              @schema[name]["oneOf"] = generate_choice_attributes(klass)
            end

            @schema
          end

          private

          def generate_choice_attributes(klass)
            klass.choice_attributes.map do |choice|
              {
                "type" => "object",
                "properties" => PropertiesCollection.from_attributes(
                  choice.attributes,
                ).to_schema,
              }
            end
          end

          def properties_to_schema(klass)
            PropertiesCollection.from_class(klass).to_schema
          end
        end
      end
    end
  end
end
