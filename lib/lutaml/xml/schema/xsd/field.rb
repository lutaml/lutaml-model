# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class Field < Base
          attribute :id, :string
          attribute :xpath, :string

          xml do
            element "field"
            mixed_content
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :xpath, to: :xpath
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :field)
        end
      end
    end
  end
end
