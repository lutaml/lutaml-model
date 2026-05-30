# frozen_string_literal: true

require "moxml"
require "moxml/adapter/nokogiri"

module Lutaml
  module Xml
    module Adapter
      class NokogiriAdapter < BaseAdapter
        MOXML_ADAPTER = Moxml::Adapter::Nokogiri
        BUILDER_CLASS = Builder::Nokogiri
        PARSED_ELEMENT_CLASS = Lutaml::Xml::NokogiriElement
      end
    end
  end
end
