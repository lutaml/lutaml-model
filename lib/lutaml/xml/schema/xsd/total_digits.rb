# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class TotalDigits < Base
          attribute :id, :string
          attribute :value, :string
          attribute :fixed, :string
          attribute :annotation, :annotation

          xml do
            element "totalDigits"
            mixed_content
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :value, to: :value
            map_attribute :fixed, to: :fixed
            map_element :annotation, to: :annotation
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :total_digits)
        end
      end
    end
  end
end
