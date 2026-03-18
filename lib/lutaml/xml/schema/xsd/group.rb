# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class Group < Base
          attribute :id, :string
          attribute :ref, :string
          attribute :name, :string
          attribute :min_occurs, :string
          attribute :max_occurs, :string
          attribute :all, :all
          attribute :choice, :choice
          attribute :sequence, :sequence
          attribute :annotation, :annotation

          xml do
            element "group"
            mixed_content
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :ref, to: :ref
            map_attribute :name, to: :name
            map_attribute :minOccurs, to: :min_occurs
            map_attribute :maxOccurs, to: :max_occurs
            map_element :annotation, to: :annotation
            map_element :sequence, to: :sequence
            map_element :choice, to: :choice
            map_element :all, to: :all
          end

          # liquid do

          #         map "child_elements", to: :child_elements

          #       end

          Lutaml::Xml::Schema::Xsd.register_model(self, :group)
        end
      end
    end
  end
end
