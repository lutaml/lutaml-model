# frozen_string_literal: true

module Lutaml
  module Xml
    module Oga
      class Element < AdapterElement
        private

        def adapter_class
          Lutaml::Xml::Adapter::OgaAdapter
        end
      end
    end
  end
end
