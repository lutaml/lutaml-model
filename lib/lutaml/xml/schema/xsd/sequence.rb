# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class Sequence < Base
          attribute :id, :string
          attribute :min_occurs, :string
          attribute :max_occurs, :string
          attribute :annotation, :annotation
          attribute :sequence, :sequence, collection: true, initialize_empty: true
          attribute :element, :element, collection: true, initialize_empty: true
          attribute :choice, :choice, collection: true, initialize_empty: true
          attribute :group, :group, collection: true, initialize_empty: true
          attribute :any, :any, collection: true, initialize_empty: true

          xml do
            root "sequence", mixed: true
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :minOccurs, to: :min_occurs
            map_attribute :maxOccurs, to: :max_occurs
            map_element :annotation, to: :annotation
            map_element :sequence, to: :sequence
            map_element :element, to: :element
            map_element :choice, to: :choice
            map_element :group, to: :group
            map_element :any, to: :any
          end

          # liquid do

          #         map "child_elements", to: :child_elements

          #       end

          Lutaml::Xml::Schema::Xsd.register_model(self, :sequence)
        end
      end
    end
  end
end
