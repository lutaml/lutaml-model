# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class SimpleType < Base
          attribute :id, :string
          attribute :name, :string
          attribute :base, :string
          attribute :final, :string
          attribute :list, :list
          attribute :union, :union
          attribute :annotation, :annotation
          attribute :restriction, :restriction_simple_type

          xml do
            root "simpleType", mixed: true
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :name, to: :name
            map_attribute :base, to: :base
            map_attribute :final, to: :final
            map_element :list, to: :list
            map_element :union, to: :union
            map_element :annotation, to: :annotation
            map_element :restriction, to: :restriction
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :simple_type)
        end
      end
    end
  end
end
