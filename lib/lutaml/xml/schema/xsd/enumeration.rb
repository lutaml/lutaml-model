# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class Enumeration < Base
          attribute :value, :string
          attribute :annotation, :annotation

          xml do
            element "enumeration"
            mixed_content
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :value, to: :value
            map_element :annotation, to: :annotation
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :enumeration)
        end
      end
    end
  end
end
