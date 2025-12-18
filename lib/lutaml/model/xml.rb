# frozen_string_literal: true

require_relative "xml/mapping_rule"
require_relative "xml/mapping"
require_relative "xml/namespace_declaration"
require_relative "xml/namespace_class_registry"
require_relative "xml/namespace_resolution_strategy"
require_relative "xml/namespace_inheritance_strategy"
require_relative "xml/qualified_inheritance_strategy"
require_relative "xml/unqualified_inheritance_strategy"
require_relative "xml/declaration_plan"
require_relative "xml/namespace_collector"
require_relative "xml/declaration_planner"
require_relative "xml/builder/nokogiri"
require_relative "xml/builder/ox"
require_relative "xml/builder/oga"

module Lutaml
  module Model
    module Xml
      def self.detect_xml_adapter
        return :nokogiri if Utils.safe_load("nokogiri", :Nokogiri)
        return :ox if Utils.safe_load("ox", :Ox)
        return :oga if Utils.safe_load("oga", :Oga)

        nil
      end
    end
  end
end

require_relative "xml_namespace"
require_relative "xml/w3c"
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
