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

        def self.generate_definitions(klass)
          defs = { klass.name => generate_class_schema(klass) }

          klass.attributes.each_value do |attr|
            generate_attribute_definitions(defs, attr)
          end

          defs
        end

        def self.generate_attribute_definitions(defs, attr)
          return unless serializable?(attr)

          defs.merge!(generate_polymorphic_definitions(attr))
          defs.merge!(generate_definitions(attr.type))
        end

        def self.generate_polymorphic_definitions(attr)
          return {} unless polymorphic?(attr)

          attr.options[:polymorphic].each_with_object({}) do |child, result|
            result.merge!(generate_definitions(child))
          end
        end

        def self.generate_class_schema(klass)
          schema = add_child_schemas(klass, base_class_schema(klass))

          # Add choice validation if present
          if klass.choice_attributes.any?
            schema["oneOf"] = generate_choice_attributes(klass)
          end

          schema
        end

        def self.base_class_schema(klass)
          {
            "type" => "object",
            "properties" => generate_properties(klass),
          }
        end

        def self.add_child_schemas(klass, schema)
          # Add inheritance if present
          return schema if klass.superclass == Lutaml::Model::Serializable

          { "allOf" => [
            { "$ref" => "#/$defs/#{klass.superclass.name}" }, schema
          ] }
        end

        def self.generate_choice_attributes(klass)
          klass.choice_attributes.map do |choice|
            {
              "type" => "object",
              "properties" => choice.attributes.to_h do |attr|
                [attr.name, generate_property_schema(attr)]
              end,
              "minProperties" => choice.min,
              "maxProperties" => choice.max,
            }
          end
        end

        def self.generate_properties(klass)
          # Get attributes defined in the current class only
          current_attributes = klass.attributes.reject do |name, _attr|
            klass.superclass.attributes.key?(name)
          end

          current_attributes.transform_values do |attr|
            generate_property_schema(attr)
          end
        end

        def self.generate_property_schema(attr)
          return collection_schema(attr) if attr.collection?
          return polymorphic_schema(attr) if serializable?(attr) && polymorphic?(attr)
          return reference_schema(attr) if serializable?(attr)

          primitive_schema(attr)
        end

        def self.collection_schema(attr)
          schema = {
            "type" => "array",
            "items" => collection_items_schema(attr),
          }

          if attr.options[:collection].is_a?(Range)
            add_collection_constraints!(schema, attr.options[:collection])
          end

          schema
        end

        def self.collection_items_schema(attr)
          if serializable?(attr)
            schema = if polymorphic?(attr)
                       polymorphic_schema(attr)
                     else
                       reference_schema(attr)
                     end
            return schema
          end

          { "type" => get_json_type(attr.type) }
        end

        def self.polymorphic_schema(attr)
          {
            "type" => ["object", "null"],
            "oneOf" => attr.options[:polymorphic].map do |type|
              { "$ref" => "#/$defs/#{type.name}" }
            end,
          }
        end

        def self.reference_schema(attr)
          { "$ref" => "#/$defs/#{attr.type.name}" }
        end

        def self.primitive_schema(attr)
          schema = {
            "type" => [get_json_type(attr.type), "null"],
          }.merge(get_json_constraints(attr))

          if polymorphic?(attr)
            schema["oneOf"] = attr.options[:polymorphic].map do |type|
              { "$ref" => "#/$defs/#{type.name}" }
            end
          end

          schema
        end

        def self.add_collection_constraints!(schema, range)
          schema["minItems"] = range.begin
          schema["maxItems"] = range.end if range.end
        end

        def self.serializable?(attr)
          !!(attr.type <= Lutaml::Model::Serialize)
        end

        def self.polymorphic?(attr)
          Utils.present?(attr.options[:polymorphic])
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

        def self.get_json_constraints(attr)
          constraints = {}

          # Add pattern validation
          constraints["pattern"] = attr.pattern.source if attr.pattern

          # Add default value
          constraints["default"] = attr.default if attr.default_set?

          # Add enumeration values
          constraints["enum"] = attr.enum_values if attr.enum?

          constraints
        end
      end
    end
  end
end
