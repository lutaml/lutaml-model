# frozen_string_literal: true

module Lutaml
  module Xml
    module Ox
      class Element < AdapterElement
        private

        def adapter_class
          Lutaml::Xml::Adapter::OxAdapter
        end
      end
    end
  end
end
