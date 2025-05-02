require "json"

module Lutaml
  module Model
    module Schema
      class JsonSchema
        def self.generate(klass, options = {})
          register = lookup_register(options[:register])
          schema = {
            "$schema" => "https://json-schema.org/draft/2020-12/schema",
            "$id" => options[:id],
            "description" => options[:description],
            "$ref" => "#/$defs/#{klass.name}",
            "$defs" => generate_definitions(klass, register),
          }.compact

          options[:pretty] ? JSON.pretty_generate(schema) : schema.to_json
        end

        def self.generate_definitions(klass, register)
          defs = { klass.name => generate_class_schema(klass, register) }
          klass.attributes.each_value do |attr|
            if attr.type(register) <= Lutaml::Model::Serialize
              defs.merge!(generate_definitions(attr.type(register), register))
            end
          end
          defs
        end

        def self.generate_class_schema(klass, register)
          {
            "type" => "object",
            "properties" => generate_properties(klass, register),
            "required" => klass.attributes.keys,
          }
        end

        def self.generate_properties(klass, register)
          klass.attributes.transform_values do |attr|
            generate_property_schema(attr, register)
          end
        end

        def self.generate_property_schema(attr, register)
          attr_type = attr.type(register)
          if attr_type <= Lutaml::Model::Serialize
            { "$ref" => "#/$defs/#{attr_type.name}" }
          elsif attr.collection?
            {
              "type" => "array",
              "items" => { "type" => get_json_type(attr_type) },
            }
          else
            { "type" => get_json_type(attr_type) }
          end
        end

        def self.get_json_type(type)
          {
            Lutaml::Model::Type::String => "string",
            Lutaml::Model::Type::Integer => "integer",
            Lutaml::Model::Type::Boolean => "boolean",
            Lutaml::Model::Type::Float => "number",
            Lutaml::Model::Type::Hash => "object",
          }[type] || "string" # Default to string for unknown types
        end

        def self.lookup_register(register)
          return register if register.is_a?(Lutaml::Model::Register)

          if register.nil?
            Lutaml::Model::Config.default_register
          else
            Lutaml::Model::GlobalRegister.lookup(register)
          end
        end
      end
    end
  end
end
