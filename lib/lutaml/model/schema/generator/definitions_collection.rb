require_relative "definition"

module Lutaml
  module Model
    module Schema
      module Generator
        class DefinitionsCollection
          class << self
            def from_class(klass)
              new.tap do |collection|
                collection << Definition.new(klass)

                process_attributes(collection, klass)
              end
            end

            def process_attributes(collection, klass)
              klass.attributes.each_value do |attribute|
                next unless attribute.serializable?

                process_attribute(collection, attribute)
              end
            end

            def process_attribute(collection, attribute)
              collection.merge(DefinitionsCollection.from_class(attribute.type))

              process_polymorphic_types(collection, attribute)
            end

            def process_polymorphic_types(collection, attribute)
              return unless attribute.options&.[](:polymorphic)

              attribute.options[:polymorphic].each do |child|
                collection.merge(DefinitionsCollection.from_class(child))
              end
            end
          end

          attr_reader :definitions

          def initialize(definitions = [])
            @definitions = definitions.map do |definition|
              next definition if definition.is_a?(Definition)

              Definition.new(definition)
            end
          end

          def to_schema
            definitions.each_with_object({}) do |definition, schema|
              schema.merge!(definition.to_schema)
            end
          end

          def add_definition(definition)
            @definitions ||= []
            @definitions << definition
          end
          alias << add_definition
          alias push add_definition

          def merge(collection)
            @definitions ||= []

            if collection.is_a?(Array)
              @definitions.concat(definitions)
            else
              @definitions.concat(collection.definitions)
            end
          end
        end
      end
    end
  end
end
