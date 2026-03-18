# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class Keyref < Base
          attribute :id, :string
          attribute :name, :string
          attribute :refer, :string
          attribute :selector, :selector
          attribute :annotation, :annotation
          attribute :field, :field, collection: true, initialize_empty: true
          # Field should be one or more

          xml do
            element "keyref"
            mixed_content
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :name, to: :name
            map_element :field, to: :field
            map_element :selector, to: :selector
            map_element :annotation, to: :annotation
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :keyref)
        end
      end
    end
  end
end
