require "moxml"
require "moxml/adapter/nokogiri"
require_relative "base_adapter"

module Lutaml
  module Xml
    module Adapter
      class NokogiriAdapter < BaseAdapter
        extend AdapterHelpers

        TEXT_CLASSES = [Moxml::Text, Moxml::Cdata].freeze
        MOXML_ADAPTER = Moxml::Adapter::Nokogiri
        BUILDER_CLASS = Builder::Nokogiri
        PARSED_ELEMENT_CLASS = Lutaml::Xml::NokogiriElement
      end
    end
  end
end
