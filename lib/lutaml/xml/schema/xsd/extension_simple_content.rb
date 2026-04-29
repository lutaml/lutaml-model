# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class ExtensionSimpleContent < Base
          attribute :id, :string
          attribute :base, :string
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
            map_element :attribute, to: :attribute
            map_element :annotation, to: :annotation
            map_element :any_attribute, to: :any_attribute
            map_element :attributeGroup, to: :attribute_group
          end

          liquid do
            map "attribute_elements", to: :attribute_elements
          end

          # Flatten attributes declared directly on the extension together
          # with those pulled in through attribute groups.
          def attribute_elements(array = [])
            array.concat(attribute)
            attribute_group.each { |group| group.attribute_elements(array) }
            array
          end

          Lutaml::Xml::Schema::Xsd.register_model(self,
                                                  :extension_simple_content)
        end
      end
    end
  end
end
