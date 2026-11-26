# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        # XSD 1.1 conditional type assignment — a type alternative on an
        # element declaration, selected by an XPath test (#1203).
        class Alternative < Base
          attribute :id, :string
          attribute :test, :string
          attribute :type, :string
          attribute :xpath_default_namespace, :string
          attribute :annotation, :annotation

          xml do
            element "alternative"
            mixed_content
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :test, to: :test
            map_attribute :type, to: :type
            map_attribute :xpathDefaultNamespace, to: :xpath_default_namespace
            map_element :annotation, to: :annotation
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :alternative)
        end
      end
    end
  end
end
