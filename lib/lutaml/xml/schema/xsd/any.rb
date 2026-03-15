# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class Any < Base
          attribute :id, :string
          attribute :min_occurs, :string
          attribute :max_occurs, :string
          attribute :namespace, :string
          attribute :process_contents, :string
          attribute :annotation, :annotation

          xml do
            root "any", mixed: true
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :namespace, to: :namespace
            map_attribute :minOccurs, to: :min_occurs
            map_attribute :maxOccurs, to: :max_occurs
            map_attribute :processContents, to: :process_contents
            map_element :annotation, to: :annotation
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :any)
        end
      end
    end
  end
end
