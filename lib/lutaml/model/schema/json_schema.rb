# lib/lutaml/model/schema/json_schema.rb
require "json"

module Lutaml
  module Model
    module Schema
      class JsonSchema
        def self.generate(klass, options = {})
          schema = {
            "$schema" => "https://json-schema.org/draft/2020-12/schema",
            "$id" => options[:id],
            "description" => options[:description],
            "$ref" => "#/$defs/#{klass.name}",
            "$defs" => generate_definitions(klass),
          }.compact

          options[:pretty] ? JSON.pretty_generate(schema) : schema.to_json
        end

        private

        def self.generate_definitions(klass)
          {
            klass.name => {
              "type" => "object",
              "properties" => generate_properties(klass),
              "required" => klass.attributes.keys,
            },
          }
        end

        def self.generate_properties(klass)
          klass.attributes.each_with_object({}) do |(name, attr), properties|
            properties[name] = generate_property_schema(attr)
          end
        end

        def self.generate_property_schema(attr)
          { "type" => get_json_type(attr.type) }
        end

        def self.get_json_type(type)
          case type
          when Lutaml::Model::Type::String
            "string"
          when Lutaml::Model::Type::Integer
            "integer"
          when Lutaml::Model::Type::Boolean
            "boolean"
          when Lutaml::Model::Type::Float
            "number"
          when Lutaml::Model::Type::Array
            "array"
          when Lutaml::Model::Type::Hash
            "object"
          else
            "string" # Default to string for unknown types
          end
        end
      end
    end
  end
end
