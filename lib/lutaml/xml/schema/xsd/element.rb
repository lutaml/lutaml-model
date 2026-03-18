# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class Element < Base
          attribute :id, :string
          attribute :ref, :string
          attribute :name, :string
          attribute :type, :string
          attribute :form, :string
          attribute :block, :string
          attribute :final, :string
          attribute :fixed, :string
          attribute :default, :string
          attribute :nillable, :string
          attribute :abstract, :boolean, default: -> { false }
          attribute :min_occurs, :string
          attribute :max_occurs, :string
          attribute :substitution_group, :string
          attribute :annotation, :annotation
          attribute :simple_type, :simple_type
          attribute :complex_type, :complex_type
          attribute :key, :key, collection: true, initialize_empty: true
          attribute :keyref, :keyref, collection: true, initialize_empty: true
          attribute :unique, :unique, collection: true, initialize_empty: true

          xml do
            element "element"
            mixed_content
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :ref, to: :ref
            map_attribute :name, to: :name
            map_attribute :type, to: :type
            map_attribute :form, to: :form
            map_attribute :block, to: :block
            map_attribute :final, to: :final
            map_attribute :fixed, to: :fixed
            map_attribute :default, to: :default
            map_attribute :nillable, to: :nillable
            map_attribute :abstract, to: :abstract
            map_attribute :minOccurs, to: :min_occurs
            map_attribute :maxOccurs, to: :max_occurs
            map_attribute :substitutionGroup, to: :substitution_group
            map_element :complexType, to: :complex_type
            map_element :simpleType, to: :simple_type
            map_element :annotation, to: :annotation
            map_element :keyref, to: :keyref
            map_element :unique, to: :unique
            map_element :key, to: :key
          end

          # liquid do

          #         map "used_by", to: :used_by

          #         map "attributes", to: :attributes

          #         map "child_elements", to: :child_elements

          #         map "referenced_type", to: :referenced_type

          #         map "min_occurrences", to: :min_occurrences

          #         map "max_occurrences", to: :max_occurrences

          #         map "referenced_name", to: :referenced_name

          #         map "referenced_object", to: :referenced_object

          #         map "referenced_complex_type", to: :referenced_complex_type

          #       end

          Lutaml::Xml::Schema::Xsd.register_model(self, :element)
        end
      end
    end
  end
end
