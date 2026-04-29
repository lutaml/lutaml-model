require "oga"
require "moxml/adapter/oga"

module Lutaml
  module Xml
    module Adapter
      class OgaAdapter < BaseAdapter
        extend AdapterHelpers

        TEXT_CLASSES = [Moxml::Text, Moxml::Cdata].freeze
        MOXML_ADAPTER = Moxml::Adapter::Oga
        BUILDER_CLASS = Builder::Oga
        PARSED_ELEMENT_CLASS = Oga::Element
      end
    end
  end
end
