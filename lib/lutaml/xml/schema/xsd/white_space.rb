# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class WhiteSpace < Base
          attribute :id, :string
          attribute :fixed, :string
          attribute :value, :string

          xml do
            element "whiteSpace"
            mixed_content
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :fixed, to: :fixed
            map_attribute :value, to: :value
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :white_space)
        end
      end
    end
  end
end
