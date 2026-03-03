# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class AttributeGroup < Base
          attribute :id, :string
          attribute :name, :string
          attribute :ref, :string
          attribute :annotation, :annotation
          attribute :any_attribute, :any_attribute
          attribute :attribute, :attribute, collection: true, initialize_empty: true
          attribute :attribute_group, :attribute_group, collection: true,
                                                        initialize_empty: true

          xml do
            root "attributeGroup", mixed: true
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :ref, to: :ref
            map_attribute :name, to: :name
            map_element :attribute, to: :attribute
            map_element :annotation, to: :annotation
            map_element :anyAttribute, to: :any_attribute
            map_element :attributeGroup, to: :attribute_group
          end

          # liquid do

          #         map "used_by", to: :used_by

          #         map "referenced_object", to: :referenced_object

          #         map "attribute_elements", to: :attribute_elements

          #       end

          Lutaml::Xml::Schema::Xsd.register_model(self, :attribute_group)
        end
      end
    end
  end
end
