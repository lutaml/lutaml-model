# frozen_string_literal: true

# Lutaml::Xml - XML serialization module for LutaML
#
# This module provides XML-specific serialization functionality.
# It requires lutaml/model to be loaded first for base classes.

# Ensure base model is loaded
require "lutaml/model"

module Lutaml
  module Xml
    # Error class for XML-specific errors
    class Error < Lutaml::Model::Error; end

    # Detect available XML adapter
    # @return [Symbol, nil] :nokogiri, :ox, :oga, :rexml, or nil
    def self.detect_xml_adapter
      return :nokogiri if Lutaml::Model::Utils.safe_load("nokogiri", :Nokogiri)
      return :ox if Lutaml::Model::Utils.safe_load("ox", :Ox)
      return :oga if Lutaml::Model::Utils.safe_load("oga", :Oga)
      return :rexml if Lutaml::Model::Utils.safe_load("rexml", :REXML)

      nil
    end

    # Autoload core classes
    autoload :Namespace, "lutaml/xml/namespace"
    autoload :Mapping, "lutaml/xml/mapping"
    autoload :MappingRule, "lutaml/xml/mapping_rule"
    autoload :Document, "lutaml/xml/document"
    autoload :Transformation, "lutaml/xml/transformation"
    autoload :Transform, "lutaml/xml/transform"
    autoload :BaseAdapter, "lutaml/xml/base_adapter"
    autoload :NokogiriAdapter, "lutaml/xml/nokogiri_adapter"
    autoload :OgaAdapter, "lutaml/xml/oga_adapter"
    autoload :OxAdapter, "lutaml/xml/ox_adapter"
    autoload :RexmlAdapter, "lutaml/xml/rexml_adapter"
    autoload :XmlElement, "lutaml/xml/xml_element"
    autoload :XmlAttribute, "lutaml/xml/xml_attribute"
    autoload :XmlNamespace, "lutaml/xml/xml_namespace"
    autoload :Decisions, "lutaml/xml/decisions"
    autoload :DeclarationPlan, "lutaml/xml/declaration_plan"
    autoload :DeclarationPlanner, "lutaml/xml/declaration_planner"
    autoload :NamespaceCollector, "lutaml/xml/namespace_collector"
    autoload :NamespaceResolver, "lutaml/xml/namespace_resolver"
    autoload :NamespaceDeclaration, "lutaml/xml/namespace_declaration"
    autoload :NamespaceClassRegistry, "lutaml/xml/namespace_class_registry"
    autoload :BlankNamespace, "lutaml/xml/blank_namespace"
    autoload :EncodingNormalizer, "lutaml/xml/encoding_normalizer"
    autoload :W3c, "lutaml/xml/w3c"
    autoload :NamespaceResolutionStrategy, "lutaml/xml/namespace_resolution_strategy"
    autoload :NamespaceInheritanceStrategy, "lutaml/xml/namespace_inheritance_strategy"
    autoload :QualifiedInheritanceStrategy, "lutaml/xml/qualified_inheritance_strategy"
    autoload :UnqualifiedInheritanceStrategy, "lutaml/xml/unqualified_inheritance_strategy"
    autoload :DataModel, "lutaml/xml/data_model"
    autoload :TransformationBuilder, "lutaml/xml/transformation_builder"
    autoload :Element, "lutaml/xml/element"
    autoload :ModelTransform, "lutaml/xml/model_transform"
    autoload :TypeNamespaceResolver, "lutaml/xml/type_namespace_resolver"
    autoload :NamespaceNeeds, "lutaml/xml/namespace_needs"
    autoload :NamespaceUsage, "lutaml/xml/namespace_usage"
    autoload :NamespaceDeclarationData, "lutaml/xml/namespace_declaration_data"
    autoload :DeclarationHandler, "lutaml/xml/declaration_handler"
    autoload :PolymorphicValueHandler, "lutaml/xml/polymorphic_value_handler"
    autoload :AttributeNamespaceResolver, "lutaml/xml/attribute_namespace_resolver"
    autoload :BlankNamespaceHandler, "lutaml/xml/blank_namespace_handler"
    autoload :DeclarationPlanQuery, "lutaml/xml/declaration_plan_query"
    autoload :DocTypeExtractor, "lutaml/xml/doctype_extractor"
    autoload :InputNamespaceExtractor, "lutaml/xml/input_namespace_extractor"
    autoload :NamespaceDeclarationBuilder, "lutaml/xml/namespace_declaration_builder"
    autoload :ElementPrefixResolver, "lutaml/xml/element_prefix_resolver"
    autoload :AdapterHelpers, "lutaml/xml/adapter_helpers"
    autoload :FormatChooser, "lutaml/xml/format_chooser"
    autoload :HoistingAlgorithm, "lutaml/xml/hoisting_algorithm"
    autoload :NamespaceInheritanceResolver, "lutaml/xml/namespace_inheritance_resolver"
    autoload :NamespaceScopeConfig, "lutaml/xml/namespace_scope_config"
    autoload :Builder, "lutaml/xml/builder"
    autoload :TypeNamespace, "lutaml/xml/type_namespace"
    autoload :TransformationSupport, "lutaml/xml/transformation_support"

    # Autoload adapter element classes (defined in subdirectories)
    autoload :NokogiriElement, "lutaml/xml/nokogiri/element"
    autoload :OxElement, "lutaml/xml/ox/element"

    # Autoload adapter module namespaces
    autoload :Nokogiri, "lutaml/xml/nokogiri"
    autoload :Oga, "lutaml/xml/oga"
    autoload :Rexml, "lutaml/xml/rexml"
  end
end

# Register XML format with the model's format registry
Lutaml::Model::FormatRegistry.register(
  :xml,
  mapping_class: Lutaml::Xml::Mapping,
  adapter_class: nil,
  transformer: Lutaml::Xml::Transform,
)

# Auto-detect and set default XML adapter
if (adapter = Lutaml::Xml.detect_xml_adapter)
  Lutaml::Model::Config.xml_adapter_type = adapter
end
