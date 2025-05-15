require_relative "definition"

module Lutaml
  module Model
    module Schema
      module Generator
        class DefinitionsCollection
          class << self
            def from_class(klass, register)
              new(register: register).tap do |collection|
                collection << Definition.new(klass, register: register)

                process_attributes(collection, klass, register)
              end
            end

            def process_attributes(collection, klass, register)
              klass.attributes.each_value do |attribute|
                next unless attribute.serializable?(register)

                process_attribute(collection, attribute, register)
              end
            end

            def process_attribute(collection, attribute, register)
              collection.merge(DefinitionsCollection.from_class(attribute.type, register))

              process_polymorphic_types(collection, attribute, register)
            end

            def process_polymorphic_types(collection, attribute, register)
              return unless attribute.options&.[](:polymorphic)

              attribute.options[:polymorphic].each do |child|
                collection.merge(DefinitionsCollection.from_class(child, register))
              end
            end
          end

          attr_reader :definitions, :register

          def initialize(definitions = [], register:)
            @register = register
            @definitions = definitions.map do |definition|
              next definition if definition.is_a?(Definition)

              Definition.new(definition, register: register)
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
              @definitions.concat(collection)
            else
              @definitions.concat(collection.definitions)
            end
          end
        end
      end
    end
  end
end
