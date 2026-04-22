# frozen_string_literal: true

require "json"

module Lutaml
  module Xml
    module Schema
      module Xsd
        # Represents a serialized schema for storage in packages
        class SerializedSchema < Lutaml::Model::Serializable
          attribute :file_path, :string
          attribute :target_namespace, :string
          attribute :schema_data, :string

          yaml do
            map "file_path", to: :file_path
            map "target_namespace", to: :target_namespace
            map "schema_data", to: :schema_data
          end

          # Create from a parsed Schema object
          # @param file_path [String] Original file path
          # @param schema [Schema] Parsed schema object
          # @return [SerializedSchema]
          def self.from_schema(file_path, schema)
            # Serialize schema to JSON instead of YAML to avoid circular reference issues
            # We'll store the essential data that can be reconstructed
            schema_hash = {
              target_namespace: schema.target_namespace,
              element_form_default: schema.element_form_default,
              attribute_form_default: schema.attribute_form_default,
              version: schema.version,
              simple_types: serialize_types(schema.simple_type),
              complex_types: serialize_types(schema.complex_type),
              elements: serialize_elements(schema.element),
              attribute_groups: serialize_attribute_groups(schema.attribute_group),
              groups: serialize_groups(schema.group),
            }

            new(
              file_path: file_path,
              target_namespace: schema.target_namespace,
              schema_data: JSON.generate(schema_hash),
            )
          end

          # Deserialize back to a Schema object
          # @return [Schema]
          def to_schema
            data = JSON.parse(schema_data)

            # Create a minimal Schema object with the essential data
            schema = Schema.new(
              target_namespace: data["target_namespace"],
              element_form_default: data["element_form_default"],
              attribute_form_default: data["attribute_form_default"],
              version: data["version"],
            )

            # Reconstruct collections
            schema.simple_type = deserialize_types(data["simple_types"],
                                                    :simple_type)
            schema.complex_type = deserialize_types(data["complex_types"],
                                                     :complex_type)
            schema.element = deserialize_elements(data["elements"])
            schema.attribute_group = deserialize_attribute_groups(data["attribute_groups"])
            schema.group = deserialize_groups(data["groups"])

            schema
          end

          private

          # Serialize type definitions to a hash
          def self.serialize_types(types)
            return [] unless types

            types.map do |type|
              {
                name: type.name,
                class: type.class.name,
              }
            end
          end

          # Deserialize types - create stub objects that behave like types
          def deserialize_types(types_data, _type_symbol)
            return [] unless types_data

            # Create stub objects that respond to common type methods
            # This avoids circular references and lutaml-model initialization issues
            types_data.map do |type_data|
              class_name = type_data["class"]
              type_name = type_data["name"]

              # Create a stub that behaves like a ComplexType/SimpleType
              Object.new.tap do |obj|
                obj.define_singleton_method(:name) { type_name }
                obj.define_singleton_method(:class) do
                  # Return a class-like object
                  Class.new do
                    define_singleton_method(:name) { class_name }
                    define_singleton_method(:to_s) { class_name }
                  end
                end
                # Add common type methods that might be called
                obj.define_singleton_method(:to_s) do
                  "#{class_name}(#{type_name})"
                end
                obj.define_singleton_method(:inspect) do
                  "#<#{class_name} name=#{type_name.inspect}>"
                end
              end
            end
          end

          # Serialize elements
          def self.serialize_elements(elements)
            return [] unless elements

            elements.map do |elem|
              {
                name: elem.name,
                type: elem.type,
              }
            end
          end

          # Deserialize elements - create simple stub objects
          def deserialize_elements(elements_data)
            return [] unless elements_data

            elements_data.map do |elem_data|
              Object.new.tap do |obj|
                obj.define_singleton_method(:name) { elem_data["name"] }
                obj.define_singleton_method(:type) { elem_data["type"] }
              end
            end
          end

          # Serialize attribute groups
          def self.serialize_attribute_groups(groups)
            return [] unless groups

            groups.map { |g| { name: g.name } }
          end

          # Deserialize attribute groups - create simple stub objects
          def deserialize_attribute_groups(groups_data)
            return [] unless groups_data

            groups_data.map do |g|
              Object.new.tap do |obj|
                obj.define_singleton_method(:name) { g["name"] }
              end
            end
          end

          # Serialize groups
          def self.serialize_groups(groups)
            return [] unless groups

            groups.map { |g| { name: g.name } }
          end

          # Deserialize groups - create simple stub objects
          def deserialize_groups(groups_data)
            return [] unless groups_data

            groups_data.map do |g|
              Object.new.tap do |obj|
                obj.define_singleton_method(:name) { g["name"] }
              end
            end
          end
        end
      end
    end
  end
end
