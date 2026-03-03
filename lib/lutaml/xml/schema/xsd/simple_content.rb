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
            root "simpleContent", mixed: true
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :base, to: :base
            map_element :restriction, to: :restriction
            map_element :annotation, to: :annotation
            map_element :extension, to: :extension
          end

          # liquid do

          #         map "attribute_elements", to: :attribute_elements

          #       end

          Lutaml::Xml::Schema::Xsd.register_model(self, :simple_content)
        end
      end
    end
  end
end
