# require "oga"
# require "moxml/adapter/oga"
# require_relative "xml_document"
# require_relative "oga/document"
# require_relative "oga/element"
# require_relative "builder/oga"

require_relative "../xml/oga_adapter"

module Lutaml
  module Model
    module XmlAdapter
      class OgaAdapter < ::Lutaml::Model::Xml::OgaAdapter
        warn "Usage of Lutaml::Model::XmlAdapter::OgaAdapter is deprecated and will be removed in the next major release. Please use Lutaml::Model::Xml::OgaAdapter instead."
      end
    end
  end
end
