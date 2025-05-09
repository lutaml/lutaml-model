require_relative "property"

module Lutaml
  module Model
    module Schema
      module Generator
        class PropertiesCollection
          class << self
            def from_class(klass)
              from_attributes(klass.attributes.values)
            end

            def from_attributes(attributes)
              new.tap do |collection|
                attributes.each do |attribute|
                  name = attribute.name
                  collection << Property.new(name, attribute)
                end
              end
            end
          end

          attr_reader :properties

          def initialize(properties = [])
            self.properties = properties
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
                             Property.new(property.name, property)
                           end
          end
          alias << add_property
          alias push add_property

          def properties=(properties)
            @properties ||= []
            @properties.clear

            @properties = properties.map do |property|
              next property if property.is_a?(Property)

              Property.new(property.name, property)
            end
          end
        end
      end
    end
  end
end
