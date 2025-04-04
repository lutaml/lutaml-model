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
        Logger.warn_future_deprication(
          old: "Lutaml::Model::XmlAdapter::OgaAdapter",
          replacement: "Lutaml::Model::Xml::OgaAdapter",
        )
      end
    end
  end
end
