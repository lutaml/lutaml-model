# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class ComplexContent < Base
          attribute :id, :string
          attribute :mixed, :boolean
          attribute :extension, :extension_complex_content
          attribute :annotation, :annotation
          attribute :restriction, :restriction_complex_content

          xml do
            root "complexContent", mixed: true
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :mixed, to: :mixed
            map_element :extension, to: :extension
            map_element :annotation, to: :annotation
            map_element :restriction, to: :restriction
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :complex_content)
        end
      end
    end
  end
end
