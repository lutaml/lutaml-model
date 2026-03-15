# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class Appinfo < Base
          attribute :source, :string
          attribute :text, :string

          xml do
            root "appinfo", mixed: true
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_content to: :text
            map_attribute :source, to: :source
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :appinfo)
        end
      end
    end
  end
end
