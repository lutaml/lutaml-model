# frozen_string_literal: true

require_relative "attribute"
require_relative "choices"

module Lutaml
  module Model
    module Schema
      module Decorators
        class ClassDefinition
          attr_accessor :base_class, :sub_classes
          attr_reader :additional_properties, :properties, :namespaced_name

          # Decorates a JSON schema information to be used in class definitions.
          # This class is used to provide a structured way to handle schema
          # information for class definitions, including attributes,
          # required fields, and JSON mappings.
          #
          # @param schema [Hash] The JSON schema to be decorated.
          # @param options [Hash] Additional options for the decorator.
          def initialize(namespaced_name, schema)
            @namespaced_name = namespaced_name
            @choices = schema["oneOf"] || []
            @additional_properties = schema["additionalProperties"] || false
            @polymorphic_attributes = []

            @properties = (schema["properties"] || {}).to_h do |name, attr|
              attribute = Decorators::Attribute.new(name, attr)
              polymorphic_attributes << attribute if attribute.polymorphic?

              [name, attribute]
            end

            @base_class = nil
            @sub_classes = []
          end

          def name
            @name ||= @namespaced_name.split("_").last
          end

          def namespaces
            @namespaces ||= @namespaced_name.split("_")[0..-2]
          end

          def parent_class
            @parent_class ||= @base_class&.namespaced_name&.gsub("_",
                                                                 "::") || "Lutaml::Model::Serializable"
          end

          def choice?
            @choices&.any?
          end

          def attributes
            return @properties.values if !choice?

            choice_attributes = {}
            @choices.each do |choice|
              choice["properties"].each do |name, attr|
                choice_attributes[name] =
                  properties[name] || Decorators::Attribute.new(name, attr)
                properties[name] = nil if properties[name]
              end
            end

            @properties.values.compact + [Choices.new(choice_attributes)]
          end

          def polymorphic?
            polymorphic_attributes.any?
          end

          def polymorphic_attributes
            return @polymorphic_attributes if !@polymorphic_attributes.nil?

            attributes.each do |attr|
              @polymorphic_attributes << attr if attr.polymorphic?
            end

            @polymorphic_attributes
          end
        end
      end
    end
  end
end
