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
            schema["$defs"].to_h do |name, definition|
              [name, generate_model_class(name, definition)]
            end
          end

          def generate_model_class(name, definition)
            template = File.join(__dir__, "templates", "model.erb")

            s = Lutaml::Model::Schema::Renderer.render(template, schema: Lutaml::Model::Schema::Decorators::ClassDefinition.new(name, definition))
          end
        end
      end
    end
  end
end
