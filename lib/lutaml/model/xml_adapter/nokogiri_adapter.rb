require "nokogiri"
require_relative "../xml/nokogiri_adapter"

module Lutaml
  module Model
    module XmlAdapter
      class NokogiriAdapter < ::Lutaml::Model::Xml::NokogiriAdapter
        Logger.warn_future_deprication(
          old: "Lutaml::Model::XmlAdapter::NokogiriAdapter",
          replacement: "Lutaml::Model::Xml::NokogiriAdapter",
        )
      end
    end
  end
end
