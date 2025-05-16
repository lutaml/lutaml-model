require_relative "definition"
require_relative "../shared_methods"

module Lutaml
  module Model
    module Schema
      module Generator
        class DefinitionsCollection
          class << self
            include SharedMethods

            def from_class(klass)
              new.tap do |collection|
                collection << Definition.new(klass)

                process_attributes(collection, klass)
              end
            end

            def process_attributes(collection, klass)
              register = extract_register_from(klass)
              klass.attributes.each_value do |attribute|
                next unless attribute.serializable?(register)

                process_attribute(collection, attribute, register)
              end
            end

            def process_attribute(collection, attribute, register)
              attr_type = Lutaml::Model::GlobalRegister.lookup(register).get_class(attribute.type)
              collection.merge(DefinitionsCollection.from_class(attr_type))

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
