require "nokogiri"
require_relative "../xml/nokogiri_adapter"

module Lutaml
  module Model
    module XmlAdapter
      class NokogiriAdapter < ::Lutaml::Model::Xml::NokogiriAdapter
        warn "Usage of Lutaml::Model::XmlAdapter::NokogiriAdapter is deprecated and will be removed in the next major release. Please use Lutaml::Model::Xml::NokogiriAdapter instead."
      end
    end
  end
end
