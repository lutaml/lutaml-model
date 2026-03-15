# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class Documentation < Base
          attribute :lang, :string
          attribute :source, :string
          attribute :content, :string

          xml do
            root "documentation"
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_all to: :content
            map_attribute :lang, to: :lang
            map_attribute :source, to: :source
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :documentation)
        end
      end
    end
  end
end
