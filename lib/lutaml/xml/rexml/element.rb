# frozen_string_literal: true

module Lutaml
  module Xml
    module Rexml
      class Element < AdapterElement
        private

        def adapter_class
          Lutaml::Xml::Adapter::RexmlAdapter
        end
      end
    end
  end
end
