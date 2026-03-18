# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class ComplexType < Base
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
            root "complexType", mixed: true
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

          # liquid do

          #         map "used_by", to: :used_by

          #         map "child_elements", to: :child_elements

          #         map "attribute_elements", to: :attribute_elements

          #       end

          # Get elements from content model (sequence, choice, or all)
          # @return [Array<Element>] Elements from content model
          def elements
            return sequence.element if sequence.respond_to?(:element)
            return choice.element if choice.respond_to?(:element)
            return all.element if all.respond_to?(:element)

            []
          end

          # Convenience plural accessor for attributes
          alias attributes attribute

          Lutaml::Xml::Schema::Xsd.register_model(self, :complex_type)
        end
      end
    end
  end
end
