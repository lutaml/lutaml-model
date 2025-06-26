require_relative "shared_methods"
require_relative "base_schema"
require_relative "renderer"
require_relative "decorators/class_definition"
require_relative "decorators/definition_collection"

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
            definitions = definition_collection_class.new(schema["$defs"])

            definitions.transform_values do |definition|
              generate_model_class(definition)
            end
          end

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
