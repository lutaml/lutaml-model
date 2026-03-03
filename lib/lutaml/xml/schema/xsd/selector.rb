# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class Selector < Base
          attribute :id, :string
          attribute :xpath, :string
          attribute :annotation, :annotation

          xml do
            root "selector", mixed: true
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :xpath, to: :xpath
            map_element :annotation, to: :annotation
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :selector)
        end
      end
    end
  end
end
