# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class ExtensionComplexContent < Base
          attribute :id, :string
          attribute :base, :string
          attribute :all, :all
          attribute :group, :group
          attribute :choice, :choice
          attribute :sequence, :sequence
          attribute :annotation, :annotation
          attribute :any_attribute, :any_attribute
          attribute :attribute, :attribute, collection: true,
                                            initialize_empty: true
          attribute :attribute_group, :attribute_group, collection: true,
                                                        initialize_empty: true

          xml do
            element "extension"
            mixed_content
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :base, to: :base
            map_element :all, to: :all
            map_element :group, to: :group
            map_element :choice, to: :choice
            map_element :sequence, to: :sequence
            map_element :attribute, to: :attribute
            map_element :annotation, to: :annotation
            map_element :any_attribute, to: :any_attribute
            map_element :attributeGroup, to: :attribute_group
          end

          liquid do
            map "attribute_elements", to: :attribute_elements
            map "referenced_object", to: :referenced_object
          end

          # Reuse the base complex type's flattened attribute list, then add
          # attributes declared directly on this extension.
          def attribute_elements(array = [])
            referenced_object&.attribute_elements(array)
            array.concat(attribute)
            attribute_group.each { |group| group.attribute_elements(array) }
            array
          end

          # Resolve the base complex type referenced by the extension.
          def referenced_object
            find_object(xsd_root.complex_type, base)
          end

          Lutaml::Xml::Schema::Xsd.register_model(self,
                                                  :extension_complex_content)
        end
      end
    end
  end
end
