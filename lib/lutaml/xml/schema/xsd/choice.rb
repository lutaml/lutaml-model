# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class Choice < Base
          attribute :id, :string
          attribute :min_occurs, :string
          attribute :max_occurs, :string
          attribute :annotation, :annotation
          attribute :any, :any, collection: true, initialize_empty: true
          attribute :group, :group, collection: true, initialize_empty: true
          attribute :choice, :choice, collection: true, initialize_empty: true
          attribute :element, :element, collection: true, initialize_empty: true
          attribute :sequence, :sequence, collection: true,
                                          initialize_empty: true

          xml do
            element "choice"
            mixed_content
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :minOccurs, to: :min_occurs
            map_attribute :maxOccurs, to: :max_occurs
            map_element :annotation, to: :annotation
            map_element :sequence, to: :sequence
            map_element :element, to: :element
            map_element :choice, to: :choice
            map_element :group, to: :group
            map_element :any, to: :any
          end

          liquid do
            map "child_elements", to: :child_elements
          end

          # Walk the choice recursively and collect contained element nodes.
          def child_elements(array = [])
            resolved_element_order&.each do |child|
              if child.is_a?(Element)
                array << child
              elsif child.respond_to?(:child_elements)
                child.child_elements(array)
              end
            end
            array
          end

          # Check whether the choice references a given element name in any
          # nested branch.
          def find_elements_used(element_name)
            resolved_element_order&.any? do |child|
              if child.is_a?(Element)
                child.ref == element_name
              elsif child.respond_to?(:find_elements_used)
                child.find_elements_used(element_name)
              end
            end || false
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :choice)
        end
      end
    end
  end
end
