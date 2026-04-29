require "rexml/document"
require "moxml"
require "moxml/adapter/rexml"

module Lutaml
  module Xml
    module Adapter
      class RexmlAdapter < BaseAdapter
        extend AdapterHelpers

        TEXT_CLASSES = [Moxml::Text, Moxml::Cdata].freeze
        MOXML_ADAPTER = Moxml::Adapter::Rexml
        BUILDER_CLASS = Builder::Rexml
        PARSED_ELEMENT_CLASS = Rexml::Element
        EMPTY_DOCUMENT_ERROR_MESSAGE = "Malformed XML: Unable to parse " \
                                       "the provided XML document. The document structure is invalid " \
                                       "or incomplete.".freeze
        EMPTY_DOCUMENT_ERROR_TYPE = :parse_exception
      end
    end
  end
end
