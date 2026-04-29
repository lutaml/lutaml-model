# frozen_string_literal: true

require "moxml/adapter/ox"
require_relative "base_adapter"

module Lutaml
  module Xml
    module Adapter
      class OxAdapter < BaseAdapter
        MOXML_ADAPTER = Moxml::Adapter::Ox
        BUILDER_CLASS = Builder::Ox
        PARSED_ELEMENT_CLASS = Ox::Element
        PARSE_ERROR_CLASS = Moxml::ParseError
      end
    end
  end
end
