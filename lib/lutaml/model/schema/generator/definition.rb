require_relative "properties_collection"
require_relative "../shared_methods"

module Lutaml
  module Model
    module Schema
      module Generator
        class Definition
          include SharedMethods

          attr_reader :type, :name

          def initialize(type)
            @type = type
            @name = type.name.gsub("::", "_")
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
                  choice.attributes, extract_register_from(type)
                ).to_schema,
              }
            end
          end

          def properties_to_schema(type)
            PropertiesCollection.from_class(type).to_schema
          end
        end
      end
    end
  end
end
