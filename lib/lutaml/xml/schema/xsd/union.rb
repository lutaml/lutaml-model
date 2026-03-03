# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class Union < Base
          attribute :id, :string
          attribute :member_types, :string, default: -> { "" }
          attribute :annotation, :annotation
          attribute :simple_type, :simple_type, collection: true,
                                                initialize_empty: true

          xml do
            root "union", mixed: true
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :memberTypes, to: :member_types
            map_element :annotation, to: :annotation
            map_element :simpleType, to: :simple_type
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :union)
        end
      end
    end
  end
end
