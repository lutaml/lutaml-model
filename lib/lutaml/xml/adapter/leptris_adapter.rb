# frozen_string_literal: true

require "moxml/adapter/leptris"

module Lutaml
  module Xml
    module Adapter
      class LeptrisAdapter < BaseAdapter
        MOXML_ADAPTER = Moxml::Adapter::Leptris
        BUILDER_CLASS = Builder::Leptris
        PARSED_ELEMENT_CLASS = Lutaml::Xml::LeptrisElement
        PARSE_ERROR_CLASS = Moxml::ParseError
      end
    end
  end
end
