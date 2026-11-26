# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        # XSD 1.1 open content — relaxes the owning complex type's content
        # model to admit foreign-namespace elements (mode: interleave or
        # suffix) (#1203).
        class OpenContent < Base
          attribute :id, :string
          attribute :mode, :string
          attribute :annotation, :annotation

          xml do
            element "openContent"
            mixed_content
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :mode, to: :mode
            map_element :annotation, to: :annotation
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :open_content)
        end
      end
    end
  end
end
