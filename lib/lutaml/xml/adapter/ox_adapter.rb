require "moxml/adapter/ox"

module Lutaml
  module Xml
    module Adapter
      class OxAdapter < BaseAdapter
        extend AdapterHelpers

        TEXT_CLASSES = [Moxml::Text, Moxml::Cdata].freeze
        MOXML_ADAPTER = Moxml::Adapter::Ox
        BUILDER_CLASS = Builder::Ox
        PARSED_ELEMENT_CLASS = Ox::Element
        PARSE_ERROR_CLASS = Moxml::ParseError
      end
    end
  end
end
