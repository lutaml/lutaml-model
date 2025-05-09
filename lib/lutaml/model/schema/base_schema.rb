require_relative "generator/definitions_collection"
# require_relative "generator/collection"
require_relative "generator/ref"

module Lutaml
  module Model
    module Schema
      class BaseSchema
        class << self
          def generate(klass, options = {})
            schema = new(
              klass,
              id: options[:id],
              title: options[:title],
              description: options[:description],
            ).generate_schema_hash

            format_schema(schema, options)
          end
        end

        attr_reader :schema, :klass
        attr_accessor :id, :title, :description

        def initialize(klass, id: nil, title: nil, description: nil)
          @klass = klass
          @id = id
          @title = title
          @description = description
        end

        def generate_schema_hash
          {
            "$schema" => "https://json-schema.org/draft/2020-12/schema",
            "$id" => id,
            "description" => description,
            "$ref" => "#/$defs/#{klass.name.gsub('::', '_')}",
            "$defs" => generate_definitions(klass),
          }.compact
        end

        private

        def polymorphic?(attr)
          Utils.present?(attr.options[:polymorphic])
        end

        def generate_definitions(klass)
          Generator::DefinitionsCollection.from_class(klass).to_schema
        end

        def generate_polymorphic_definitions(attr)
          return {} unless polymorphic?(attr)

          attr.options[:polymorphic].each_with_object({}) do |child, result|
            result.merge!(generate_definitions(child))
          end
        end
      end
    end
  end
end
