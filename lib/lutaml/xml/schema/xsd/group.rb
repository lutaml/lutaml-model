# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class Group < Base
          attribute :id, :string
          attribute :ref, :string
          attribute :name, :string
          attribute :min_occurs, :string
          attribute :max_occurs, :string
          attribute :all, :all
          attribute :choice, :choice
          attribute :sequence, :sequence
          attribute :annotation, :annotation

          xml do
            element "group"
            mixed_content
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :ref, to: :ref
            map_attribute :name, to: :name
            map_attribute :minOccurs, to: :min_occurs
            map_attribute :maxOccurs, to: :max_occurs
            map_element :annotation, to: :annotation
            map_element :sequence, to: :sequence
            map_element :choice, to: :choice
            map_element :all, to: :all
          end

          liquid do
            map "child_elements", to: :child_elements
          end

          # Walk the referenced group definition and collect its element
          # children recursively.
          def child_elements(array = [])
            group = referenced_object
            return array unless group

            group.resolved_element_order&.each do |child|
              if child.is_a?(Element)
                array << child
              elsif child.respond_to?(:child_elements)
                child.child_elements(array)
              end
            end
            array
          end

          # Check whether the group references a given element name anywhere
          # in its nested content model.
          def find_elements_used(element_name)
            resolved_element_order&.any? do |child|
              if child.is_a?(Element)
                reference_matches?(element_name, child.ref || child.name)
              elsif child.respond_to?(:find_elements_used)
                child.find_elements_used(element_name)
              end
            end || false
          end

          # Return the group itself when it is named, otherwise resolve the
          # root-level group referenced by `ref`.
          def referenced_object
            return self if name

            find_object(xsd_root.group)
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :group)
        end
      end
    end
  end
end
