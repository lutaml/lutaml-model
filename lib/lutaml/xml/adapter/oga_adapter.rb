# frozen_string_literal: true

require "oga"
require "moxml/adapter/oga"

module Lutaml
  module Xml
    module Adapter
      # @deprecated the Oga engine is on the deprecation path — moxml's
      # default engine (Nokogiri, or the leptris native engine when
      # present) is the supported XML lane. Selection emits a
      # deprecation warning; removal lands in a future release.
      class OgaAdapter < BaseAdapter
        MOXML_ADAPTER = Moxml::Adapter::Oga
        BUILDER_CLASS = Builder::Oga
        PARSED_ELEMENT_CLASS = Oga::Element
      end
    end
  end
end
