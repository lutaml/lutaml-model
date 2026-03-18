# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class MinLength < Base
          attribute :fixed, :string
          attribute :value, :integer

          xml do
            element "minLength"
            mixed_content
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :value, to: :value
            map_attribute :fixed, to: :fixed
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :min_length)
        end
      end
    end
  end
end
