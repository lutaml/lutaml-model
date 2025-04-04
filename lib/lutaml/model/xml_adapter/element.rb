# require "ox"
# require_relative "xml_document"
# require_relative "builder/ox"

require_relative "../xml/element"

module Lutaml
  module Model
    module XmlAdapter
      class Element < ::Lutaml::Model::Xml::Element
        Logger.warn_future_deprication(
          old: "Lutaml::Model::XmlAdapter::Element",
          replacement: "Lutaml::Model::Xml::Element",
        )
      end
    end
  end
end
