# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class Unique < Base
          attribute :id, :string
          attribute :name, :string
          attribute :selector, :selector
          attribute :annotation, :annotation
          attribute :field, :field, collection: true, initialize_empty: true

          xml do
            root "unique", mixed: true
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :name, to: :name
            map_element :annotation, to: :annotation
            map_element :selector, to: :selector
            map_element :field, to: :field
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :unique)
        end
      end
    end
  end
end
