# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class Length < Base
          attribute :fixed, :boolean
          attribute :value, :integer
          attribute :annotation, :annotation

          xml do
            root "length", mixed: true
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :fixed, to: :fixed
            map_attribute :value, to: :value
            map_element :annotation, to: :annotation
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :length)
        end
      end
    end
  end
end
