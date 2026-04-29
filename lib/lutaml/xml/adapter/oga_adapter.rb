# frozen_string_literal: true

require "oga"
require "moxml/adapter/oga"
require_relative "base_adapter"

module Lutaml
  module Xml
    module Adapter
      class OgaAdapter < BaseAdapter
        MOXML_ADAPTER = Moxml::Adapter::Oga
        BUILDER_CLASS = Builder::Oga
        PARSED_ELEMENT_CLASS = Oga::Element
      end
    end
  end
end
