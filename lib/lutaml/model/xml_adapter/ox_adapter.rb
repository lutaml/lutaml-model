# require "ox"
# require_relative "xml_document"
# require_relative "builder/ox"

require_relative "../xml/ox_adapter"

module Lutaml
  module Model
    module XmlAdapter
      class OxAdapter < ::Lutaml::Model::Xml::OxAdapter
        Logger.warn_future_deprecation(
          old: "Lutaml::Model::XmlAdapter::OxAdapter",
          replacement: "Lutaml::Model::Xml::OxAdapter",
        )
      end
    end
  end
end
