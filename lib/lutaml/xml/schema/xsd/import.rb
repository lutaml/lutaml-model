# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class Import < Base
          attribute :id, :string
          attribute :namespace, :string
          attribute :schema_path, :string
          attribute :annotation, :annotation

          xml do
            root "import", mixed: true
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_attribute :namespace, to: :namespace
            map_attribute :schemaLocation, to: :schema_path
            map_element :annotation, to: :annotation
          end

          def fetch_schema
            Glob.include_schema(schema_path) if schema_path && Glob.location?
          end

          Lutaml::Xml::Schema::Xsd.register_model(self, :import)
        end
      end
    end
  end
end
