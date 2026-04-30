# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class AttributeGroup < Base
          attribute :id, :string
          attribute :name, :string
          attribute :ref, :string
          attribute :annotation, :annotation
          attribute :any_attribute, :any_attribute
          attribute :attribute, :attribute, collection: true,
                                            initialize_empty: true
          attribute :attribute_group, :attribute_group, collection: true,
                                                        initialize_empty: true

          xml do
            element "attributeGroup"
            mixed_content
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :ref, to: :ref
            map_attribute :name, to: :name
            map_element :attribute, to: :attribute
            map_element :annotation, to: :annotation
            map_element :anyAttribute, to: :any_attribute
            map_element :attributeGroup, to: :attribute_group
          end

          liquid do
            map "used_by", to: :used_by
            map "referenced_object", to: :referenced_object
            map "attribute_elements", to: :attribute_elements
          end

          # Return complex types that reference this attribute group.
          def used_by
            xsd_root.complex_type.select { |type| find_used_by(type) }
          end

          # Flatten nested attribute-group references into a single list of
          # attribute objects for template consumption.
          def attribute_elements(array = [])
            group = referenced_object
            return array unless group

            group.resolved_element_order&.each do |child|
              case child
              when AttributeGroup
                if child.referenced_object
                  child.attribute_elements(array)
                else
                  array << child
                end
              when Attribute
                array << child
              end
            end
            array
          end

          # Recursively inspect nested content to determine whether the given
          # object references this attribute group.
          def find_used_by(object)
            object&.resolved_element_order&.any? do |child|
              if child.is_a?(AttributeGroup)
                child.ref == name
              else
                find_used_by(child)
              end
            end || false
          end

          # Return the attribute group itself when it is named, otherwise
          # resolve the root-level group referenced by `ref`.
          def referenced_object
            return self if name

            find_object(xsd_root.attribute_group)
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :attribute_group)
        end
      end
    end
  end
end
