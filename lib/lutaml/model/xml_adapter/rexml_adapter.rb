require_relative "../xml/rexml_adapter"

module Lutaml
  module Model
    module XmlAdapter
      class RexmlAdapter < ::Lutaml::Model::Xml::RexmlAdapter
        Logger.warn_future_deprecation(
          old: "Lutaml::Model::XmlAdapter::RexmlAdapter",
          replacement: "Lutaml::Model::Xml::RexmlAdapter",
        )
      end
    end
  end
end
