# frozen_string_literal: true

require "json"

module Lutaml
  module Json
    module Schema
      # JSON Schema generator for Lutaml models
      #
      # Generates JSON Schema from Lutaml model classes.
      # Extends the shared BaseSchema infrastructure.
      class JsonSchema < Lutaml::Model::Schema::BaseSchema
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
            definitions = definition_collection_class.new(schema["$defs"])

            definitions.transform_values do |definition|
              generate_model_class(definition)
            end
          end

          private

          def generate_model_class(schema)
            template = File.join(__dir__, "..", "..", "model", "schema", "templates", "model.erb")

            Lutaml::Model::Schema::Renderer.render(template, schema: schema)
          end

          def definition_collection_class
            Lutaml::Model::Schema::Decorators::DefinitionCollection
          end
        end
      end
    end
  end
end
