# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class MaxInclusive < Base
          attribute :value, :string

          xml do
            element "maxInclusive"
            mixed_content
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :value, to: :value
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :max_inclusive)
        end
      end
    end
  end
end
