# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class SimpleContent < Base
          attribute :id, :string
          attribute :base, :string
          attribute :annotation, :annotation
          attribute :extension, :extension_simple_content
          attribute :restriction, :restriction_simple_content

          xml do
            element "simpleContent"
            mixed_content
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :base, to: :base
            map_element :restriction, to: :restriction
            map_element :annotation, to: :annotation
            map_element :extension, to: :extension
          end

          liquid do
            map "attribute_elements", to: :attribute_elements
          end

          # Collect attributes inherited from the base complex type together
          # with attributes added by the simple-content extension.
          def attribute_elements(array = [])
            base_complex_type&.attribute_elements(array)
            extension&.attribute_elements(array)
            array
          end

          # Resolve the effective base type from inline, extension, or
          # restriction declarations.
          def base_type
            base ||
              extension&.base ||
              restriction&.base
          end

          private

          # Resolve the complex type that provides inherited attributes for
          # this simple-content definition, if one exists.
          def base_complex_type
            find_object(__root.complex_type, base_type)
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :simple_content)
        end
      end
    end
  end
end
