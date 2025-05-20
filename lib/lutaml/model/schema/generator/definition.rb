require_relative "properties_collection"

module Lutaml
  module Model
    module Schema
      module Generator
        class Definition
          attr_reader :type, :name, :register

          def initialize(type, register:)
            @type = type
            @name = type.name.gsub("::", "_")
            @register = register
          end

          def to_schema
            @schema = {
              name => {
                "type" => "object",
                "additionalProperties" => false,
                "properties" => properties_to_schema(type),
              },
            }

            # Add choice validation if present
            if type.choice_attributes.any?
              @schema[name]["oneOf"] = generate_choice_attributes(type)
            end

            @schema
          end

          private

          def generate_choice_attributes(type)
            type.choice_attributes.map do |choice|
              {
                "type" => "object",
                "properties" => PropertiesCollection.from_attributes(
                  choice.attributes,
                  register,
                ).to_schema,
              }
            end
          end

          def properties_to_schema(type)
            PropertiesCollection.from_class(type, register).to_schema
          end
        end
      end
    end
  end
end
