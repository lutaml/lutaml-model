# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class ComplexType < Base
          DIRECT_CHILD_ELEMENTS_EXCEPTION = %w[
            AttributeGroup
            AnyAttribute
            Annotation
            Attribute
          ].freeze

          attribute :id, :string
          attribute :name, :string
          attribute :base, :string
          attribute :final, :string
          attribute :block, :string
          attribute :mixed, :boolean, default: -> { false }
          attribute :abstract, :boolean, default: -> { false }
          attribute :all, :all
          attribute :group, :group
          attribute :choice, :choice
          attribute :sequence, :sequence
          attribute :annotation, :annotation
          attribute :simple_content, :simple_content
          attribute :complex_content, :complex_content
          attribute :attribute, :attribute, collection: true,
                                            initialize_empty: true
          attribute :attribute_group, :attribute_group, collection: true,
                                                        initialize_empty: true

          xml do
            element "complexType"
            mixed_content
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :name, to: :name
            map_attribute :base, to: :base
            map_attribute :final, to: :final
            map_attribute :block, to: :block
            map_attribute :mixed, to: :mixed
            map_attribute :abstract, to: :abstract
            map_element :all, to: :all
            map_element :group, to: :group
            map_element :choice, to: :choice
            map_element :sequence, to: :sequence
            map_element :attribute, to: :attribute
            map_element :annotation, to: :annotation
            map_element :attributeGroup, to: :attribute_group
            map_element :simpleContent, to: :simple_content
            map_element :complexContent, to: :complex_content
          end

          liquid do
            map "used_by", to: :used_by
            map "child_elements", to: :child_elements
            map "attribute_elements", to: :attribute_elements
          end

          # Return root-level elements and nested child elements that refer to
          # this complex type by name.
          def used_by
            root_complex_types = __root.complex_type.reject { |complex_type| complex_type == self }
            raw_elements = __root.group.flat_map(&:child_elements)
            raw_elements.concat(__root.element)
            raw_elements.concat(root_complex_types.flat_map(&:child_elements))
            raw_elements.select { |element| reference_matches?(name, element.type) }
          end

          # Flatten attributes declared directly on the complex type and those
          # brought in through groups and content extensions.
          def attribute_elements(array = [])
            array.concat(attribute)
            attribute_group.each { |group| group.attribute_elements(array) }
            simple_content&.attribute_elements(array)
            complex_content&.attribute_elements(array)
            array
          end

          # Return structural children while skipping attributes and other
          # non-element content wrappers listed in the exception set.
          def direct_child_elements(array = [], except: DIRECT_CHILD_ELEMENTS_EXCEPTION)
            resolved_element_order&.each do |child|
              next if except.any? { |klass| child.class.name.include?("::#{klass}") }

              array << child if child.resolved_element_order&.any?
            end
            array
          end

          # Walk nested content containers and collect the element nodes they
          # expose in document order.
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

          # Check whether a referenced element name is used anywhere within
          # this complex type's nested content model.
          def find_elements_used(element_name)
            resolved_element_order&.any? do |child|
              if child.is_a?(Element)
                reference_matches?(element_name, child.ref || child.name)
              elsif child.respond_to?(:find_elements_used)
                child.find_elements_used(element_name)
              end
            end || false
          end

          # Recursively inspect another object to see whether it references
          # this complex type through nested attribute groups.
          def find_used_by(object)
            object&.resolved_element_order&.any? do |child|
              if child.is_a?(AttributeGroup)
                child.ref == name
              else
                find_used_by(child)
              end
            end || false
          end

          # Get elements from the primary content model (sequence, choice, or all).
          # @return [Array<Element>] Elements exposed by the active content model
          def elements
            return sequence.element if sequence.respond_to?(:element)
            return choice.element if choice.respond_to?(:element)
            return all.element if all.respond_to?(:element)

            []
          end

          # Convenience plural accessor for attributes.
          alias attributes attribute

          Lutaml::Xml::Schema::Xsd.register_model(self, :complex_type)
        end
      end
    end
  end
end
