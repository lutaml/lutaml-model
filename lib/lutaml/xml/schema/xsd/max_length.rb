# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class MaxLength < Base
          attribute :fixed, :string
          attribute :value, :integer

          xml do
            root "maxLength", mixed: true
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :value, to: :value
            map_attribute :fixed, to: :fixed
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :max_length)
        end
      end
    end
  end
end
