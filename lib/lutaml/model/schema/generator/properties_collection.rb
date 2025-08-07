require_relative "property"
require_relative "../shared_methods"

module Lutaml
  module Model
    module Schema
      module Generator
        class PropertiesCollection
          class << self
            include SharedMethods

            def from_class(klass)
              from_attributes(klass.attributes.values, extract_register_from(klass))
            end

            def from_attributes(attributes, register)
              new(register: register).tap do |collection|
                attributes.each do |attribute|
                  name = attribute.name
                  collection << Property.new(name, attribute, register: register)
                end
              end
            end
          end

          attr_reader :properties, :__register

          def initialize(properties = [], register:)
            self.properties = properties
            @__register = register
          end

          def to_schema
            properties.each_with_object({}) do |property, schema|
              schema.merge!(property.to_schema)
            end
          end

          def add_property(property)
            @properties << if property.is_a?(Property)
                             property
                           else
                             Property.new(property.name, property, register: __register)
                           end
          end
          alias << add_property
          alias push add_property

          def properties=(properties)
            @properties ||= []
            @properties.clear

            @properties = properties.map do |property|
              next property if property.is_a?(Property)

              Property.new(property.name, property, __register)
            end
          end
        end
      end
    end
  end
end
