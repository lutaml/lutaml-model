# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class Redefine < Base
          attribute :id, :string
          attribute :schema_path, :string
          attribute :group, :group
          attribute :annotation, :annotation
          attribute :simple_type, :simple_type
          attribute :complex_type, :complex_type
          attribute :attribute_group, :attribute_group

          xml do
            element "redefine"
            mixed_content
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :schemaLocation, to: :schema_path
            map_element :group, to: :group
            map_element :annotation, to: :annotation
            map_element :simpleType, to: :simple_type
            map_element :complexType, to: :complex_type
            map_element :attributeGroup, to: :attribute_group
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :redefine)
        end
      end
    end
  end
end
