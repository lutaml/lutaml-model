require_relative "base_schema"
require "yaml"

module Lutaml
  module Model
    module Schema
      class YamlSchema < BaseSchema
        class << self
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
            <<~SCHEMA
              %YAML 1.1
              #{options[:pretty] ? schema.to_yaml : YAML.dump(schema)}
            SCHEMA
          end

          def generate_model_classes(schema)
            definitions = definition_collection_class.new(schema["$defs"])

            definitions.transform_values do |definition|
              generate_model_class(definition)
            end
          end

          private

          def generate_model_class(schema)
            template = File.join(__dir__, "templates", "model.erb")

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
