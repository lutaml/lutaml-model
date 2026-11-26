# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        # XSD 1.1 assertion — an XPath predicate evaluated against the
        # owning complex type's instance (#1203).
        class Assert < Base
          attribute :id, :string
          attribute :test, :string
          attribute :xpath_default_namespace, :string
          attribute :annotation, :annotation

          xml do
            element "assert"
            mixed_content
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :test, to: :test
            map_attribute :xpathDefaultNamespace, to: :xpath_default_namespace
            map_element :annotation, to: :annotation
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :assert)
        end
      end
    end
  end
end
