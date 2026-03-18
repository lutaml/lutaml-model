# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class Key < Base
          attribute :id, :string
          attribute :name, :string
          attribute :selector, :selector
          attribute :annotation, :annotation
          attribute :field, :field, collection: true, initialize_empty: true
          # Field should be one or more

          xml do
            element "key"
            mixed_content
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :name, to: :name
            map_element :annotation, to: :annotation
            map_element :selector, to: :selector
            map_element :field, to: :field
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :key)
        end
      end
    end
  end
end
