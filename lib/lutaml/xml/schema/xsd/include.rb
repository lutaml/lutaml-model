# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class Include < Base
          attribute :id, :string
          attribute :schema_path, :string
          attribute :annotation, :annotation

          xml do
            element "include"
            mixed_content
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :schemaLocation, to: :schema_path
            map_element :annotation, to: :annotation
          end

          def fetch_schema
            Glob.include_schema(schema_path)
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :include)
        end
      end
    end
  end
end
