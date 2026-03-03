# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        class Annotation < Base
          attribute :id, :string
          attribute :documentation, :documentation, collection: true,
                                                    initialize_empty: true
          attribute :appinfo, :appinfo, collection: true, initialize_empty: true

          xml do
            root "annotation", mixed: true
            namespace Lutaml::Xml::Schema::XsdNamespace

            map_attribute :id, to: :id
            map_element :documentation, to: :documentation
            map_element :appinfo, to: :appinfo
          end

          # Convenience plural accessor for collections
          alias documentations documentation

          Lutaml::Xml::Schema::Xsd.register_model(self, :annotation)
        end
      end
    end
  end
end
