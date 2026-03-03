# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class All < Base
          attribute :id, :string
          attribute :max_occurs, :string
          attribute :min_occurs, :string
          attribute :annotation, :annotation
          attribute :element, :element, collection: true, initialize_empty: true

          xml do
            root "all", mixed: true
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :max_occurs, to: :max_occurs
            map_attribute :min_occurs, to: :min_occurs
            map_element :annotation, to: :annotation
            map_element :element, to: :element
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :all)
        end
      end
    end
  end
end
