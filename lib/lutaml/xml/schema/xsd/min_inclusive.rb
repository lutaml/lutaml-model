# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class MinInclusive < Base
          attribute :value, :string

          xml do
            root "minInclusive", mixed: true
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :value, to: :value
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :min_inclusive)
        end
      end
    end
  end
end
