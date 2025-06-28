# frozen_string_literal: true

require_relative "attribute"

module Lutaml
  module Model
    module Schema
      module Decorators
        class Choices
          attr_reader :attributes

          # Decorates a collection of choice attributes.
          # This class is used to handle attributes that are part of a choice
          # constraint in a JSON schema. It provides a way to access the choice
          # attributes in a structured manner.
          def initialize(attributes)
            @attributes = attributes.values
          end

          def choice?
            true
          end
        end

        class ClassDefinition
          # Decorates a JSON schema information to be used in class definitions.
          # This class is used to provide a structured way to handle schema
          # information for class definitions, including attributes,
          # required fields, and JSON mappings.
          #
          # @param schema [Hash] The JSON schema to be decorated.
          # @param options [Hash] Additional options for the decorator.
          def initialize(schema, options = {})
            @schema = schema
            @options = options
          end

          def name
            @name ||= @schema.split("_").last
          end

          def namespaces
            @namespaces ||= @schema.split("_")[0..-2]
          end

          def attributes
            return @attributes if @attributes

            choice_attributes = {}

            @options["oneOf"]&.each do |choice|
              choice["properties"].each do |name, attr|
                choice_attributes[name] = Decorators::Attribute.new(name, attr)
              end
            end

            @attributes ||= @options["properties"].map do |name, attr|
              next if choice_attributes[name]

              Decorators::Attribute.new(name, attr)
            end.compact

            @attributes << Choices.new(choice_attributes) if choice_attributes.any?

            @attributes
          end
        end
      end
    end
  end
end
