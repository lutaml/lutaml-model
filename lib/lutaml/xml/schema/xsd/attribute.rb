# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class Attribute < Base
          attribute :id, :string
          attribute :use, :string, values: %w[required prohibited optional], default: -> {
            "optional"
          }
          attribute :ref, :string
          attribute :name, :string
          attribute :type, :string
          attribute :form, :string
          attribute :fixed, :string
          attribute :default, :string
          attribute :annotation, :annotation
          attribute :simple_type, :simple_type

          xml do
            element "attribute"
            mixed_content
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :use, to: :use
            map_attribute :ref, to: :ref
            map_attribute :name, to: :name
            map_attribute :type, to: :type
            map_attribute :form, to: :form
            map_attribute :fixed, to: :fixed
            map_attribute :default, to: :default
            map_element :annotation, to: :annotation
            map_element :simpleType, to: :simple_type
          end

          liquid do
            map "cardinality", to: :cardinality
            map "referenced_name", to: :referenced_name
            map "referenced_type", to: :referenced_type
            map "referenced_object", to: :referenced_object
          end

          # Translate XSD attribute `use` semantics into the cardinality
          # strings expected by Liquid templates.
          def cardinality
            case use
            when "required" then "1"
            when "optional" then "0..1"
            end
          end

          # Resolve the effective type, following `ref` when needed.
          def referenced_type
            referenced_object&.type
          end

          # Resolve the effective attribute name, falling back to the raw
          # `ref` when the target cannot be found.
          def referenced_name
            referenced_object&.name || ref
          end

          # Return the attribute itself when it is named, otherwise resolve
          # the root-level attribute referenced by `ref`.
          def referenced_object
            return self if name

            find_object(xsd_root.attribute)
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :attribute)
        end
      end
    end
  end
end
