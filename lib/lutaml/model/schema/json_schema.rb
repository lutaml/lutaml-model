require_relative "shared_methods"
require_relative "base_schema"
require_relative "renderer"
require_relative "decorators/class_definition"

require "json"

module Lutaml
  module Model
    module Schema
      class JsonSchema < BaseSchema
        class << self
          include Lutaml::Model::Schema::SharedMethods

          def generate(
            klass,
            id: nil,
            title: nil,
            description: nil,
            pretty: false
          )
            options = {
              schema: "https://json-schema.org/draft/2020-12/schema",
              id: id,
              title: title,
              description: description,
              pretty: pretty,
            }

            super(klass, options)
          end

          def format_schema(schema, options)
            options[:pretty] ? JSON.pretty_generate(schema) : schema.to_json
          end

          def generate_model_classes(schema)
            polymorphic_classes = []

            heirarchies = generate_heirarchies(schema["$defs"])

            schema["$defs"].to_h do |name, definition|
              schema = definition_class.new(name, definition, heirarchies: heirarchies)

              [name, generate_model_class(name, schema)]
            end
          end

          def generate_model_class(name, schema)
            template = File.join(__dir__, "templates", "model.erb")

            Lutaml::Model::Schema::Renderer.render(template, schema: schema)
          end

          def generate_heirarchies(definitions)
            definitions.each_with_object({}) do |(_name, schema), heirarchies|
              polymorphic_properties = {}

              schema["properties"]&.each do |property_name, property|
                if polymorphic?(property)
                  polymorphic_properties[property_name] = property["oneOf"].map do |option|
                    option["$ref"].split("/").last # .gsub("_", "::")
                  end
                end
              end

              polymorphic_properties.each do |property_name, options|
                parent_class = { name: options.first, schema: definitions[options.first] }

                options.each do |option|
                  current_class = { name: option, schema: definitions[option] }

                  current_attributes = (current_class[:schema]["properties"] || {}).keys
                  parent_attributes = (parent_class[:schema]["properties"] || {}).keys

                  if (current_attributes - parent_attributes).empty? && (parent_attributes - current_attributes).any?
                    parent_class = current_class
                  end
                end

                children = options - [parent_class[:name]]
                children.each do |child_name|
                  heirarchies[child_name] = parent_class[:name].gsub("_", "::")
                end

                # heirarchies[property_name] = {
                #   parent: parent_class[:name],
                #   children: options - [parent_class[:name]],
                # }
              end
            end
          end

          def definition_class
            Lutaml::Model::Schema::Decorators::ClassDefinition
          end

          def polymorphic?(property)
            return false unless property["oneOf"]

            (
              (property["type"] == "object") ||
              (
                property["type"].is_a?(Array) &&
                property["type"].first == "object"
              )
            ) && property["oneOf"].count > 1
          end
        end
      end
    end
  end
end
