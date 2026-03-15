# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class Notation < Base
          attribute :id, :string
          attribute :name, :string
          attribute :public, :string
          attribute :system, :string
          attribute :annotation, :annotation

          xml do
            root "notation", mixed: true
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :name, to: :name
            map_attribute :public, to: :public
            map_attribute :system, to: :system
            map_element :annotation, to: :annotation
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :notation)
        end
      end
    end
  end
end
