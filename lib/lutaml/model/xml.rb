# frozen_string_literal: true

module Lutaml
  module Model
    module Xml
      def self.detect_xml_adapter
        return :nokogiri if Object.const_defined?(:Nokogiri)
        return :ox if Object.const_defined?(:Ox)
        return :oga if Object.const_defined?(:Oga)
        return :rexml if Utils.safe_load("rexml", :REXML)

        nil
      end
    end
  end
end

require_relative "xml/document"
require_relative "xml/mapping"
require_relative "xml/mapping_rule"
require_relative "xml/transform"

Lutaml::Model::FormatRegistry.register(
  :xml,
  mapping_class: Lutaml::Model::Xml::Mapping,
  adapter_class: nil,
  transformer: Lutaml::Model::Xml::Transform,
)

if (adapter = Lutaml::Model::Xml.detect_xml_adapter)
  Lutaml::Model::Config.xml_adapter_type = adapter
end
