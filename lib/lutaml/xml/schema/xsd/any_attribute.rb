# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class AnyAttribute < Base
          attribute :id, :string
          attribute :namespace, :string
          attribute :process_contents, :string
          attribute :annotation, :annotation

          xml do
            root "anyAttribute", mixed: true
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :namespace, to: :namespace
            map_attribute :processContents, to: :process_contents
            map_element :annotation, to: :annotation
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :any_attribute)
        end
      end
    end
  end
end
