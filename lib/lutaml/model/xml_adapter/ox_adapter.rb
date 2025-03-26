# require "ox"
# require_relative "xml_document"
# require_relative "builder/ox"

require_relative "../xml/ox_adapter"

module Lutaml
  module Model
    module XmlAdapter
      class OxAdapter < ::Lutaml::Model::Xml::OxAdapter
        warn "Usage of Lutaml::Model::XmlAdapter::OxAdapter is deprecated and will be removed in the next major release. Please use Lutaml::Model::Xml::OxAdapter instead."
      end
    end
  end
end
