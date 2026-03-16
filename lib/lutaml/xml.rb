# frozen_string_literal: true

# Lutaml::Xml - XML serialization module for LutaML
#
# This module provides XML-specific serialization functionality.
# It requires lutaml/model to be loaded first for base classes.

# Ensure base model is loaded
require_relative "model"

module Lutaml
  module Xml
    # Error module for XML-specific errors
    module Error
      autoload :XmlError, "#{__dir__}/xml/error/xml_error"
      autoload :InvalidNamespaceError, "#{__dir__}/xml/error/invalid_namespace_error"
      autoload :InvalidXsdTypeError, "#{__dir__}/xml/error/invalid_xsd_type_error"
      autoload :XmlConfigurationError, "#{__dir__}/xml/error/xml_configuration_error"
      autoload :NamespaceMismatchError, "#{__dir__}/xml/error/namespace_mismatch_error"
    end

    # XML Configuration modules
    autoload :Configurable, "#{__dir__}/xml/configurable"
    autoload :NamespaceTypeResolver, "#{__dir__}/xml/namespace_type_resolver"

    # XML Type modules
    module Type
      autoload :ValueXmlMapping, "#{__dir__}/xml/type/value_xml_mapping"
      autoload :Configurable, "#{__dir__}/xml/type/configurable"
    end

    # XML Serialization modules
    autoload :Serialization, "#{__dir__}/xml/serialization"

    # XML Schema modules
    module Schema
      autoload :XsdSchema, "#{__dir__}/xml/schema/xsd_schema"
      autoload :RelaxngSchema, "#{__dir__}/xml/schema/relaxng_schema"
      autoload :Builder, "#{__dir__}/xml/schema/builder"
      autoload :BuiltinTypes, "#{__dir__}/xml/schema/builtin_types"
    end

    # Detect available XML adapter
    # @return [Symbol, nil] :nokogiri, :ox, :oga, :rexml, or nil
    def self.detect_xml_adapter
      return :nokogiri if Lutaml::Model::Utils.safe_load("nokogiri", :Nokogiri)
      return :ox if Lutaml::Model::Utils.safe_load("ox", :Ox)
      return :oga if Lutaml::Model::Utils.safe_load("oga", :Oga)
      return :rexml if Lutaml::Model::Utils.safe_load("rexml", :REXML)

      nil
    end

    # Get the current XML adapter
    #
    # Provides unified access to the configured XML adapter.
    # This is a convenience method for consistent adapter access across
    # Model and Type classes.
    #
    # @return [Object] the configured XML adapter instance
    #
    # @example Using the adapter
    #   adapter = Lutaml::Xml.adapter
    #   doc = adapter.parse(xml_string)
    #
    def self.adapter
      Lutaml::Model::Config.adapter_for(:xml)
    end

    # Get the current XML adapter type
    #
    # @return [Symbol] the configured XML adapter type (:nokogiri, :ox, etc.)
    def self.adapter_type
      Lutaml::Model::Config.xml_adapter_type
    end

    # Autoload core classes
    autoload :Namespace, "#{__dir__}/xml/namespace"
    autoload :Mapping, "#{__dir__}/xml/mapping"
    autoload :MappingRule, "#{__dir__}/xml/mapping_rule"
    autoload :Document, "#{__dir__}/xml/document"
    autoload :Transformation, "#{__dir__}/xml/transformation"
    autoload :Transform, "#{__dir__}/xml/transform"
    autoload :Adapter, "#{__dir__}/xml/adapter"
    autoload :XmlElement, "#{__dir__}/xml/xml_element"
    autoload :XmlAttribute, "#{__dir__}/xml/xml_attribute"
    autoload :Decisions, "#{__dir__}/xml/decisions"
    autoload :DeclarationPlan, "#{__dir__}/xml/declaration_plan"
    autoload :DeclarationPlanner, "#{__dir__}/xml/declaration_planner"
    autoload :NamespaceCollector, "#{__dir__}/xml/namespace_collector"
    autoload :NamespaceResolver, "#{__dir__}/xml/namespace_resolver"
    autoload :NamespaceDeclaration, "#{__dir__}/xml/namespace_declaration"
    autoload :NamespaceClassRegistry, "#{__dir__}/xml/namespace_class_registry"
    autoload :BlankNamespace, "#{__dir__}/xml/blank_namespace"
    autoload :EncodingNormalizer, "#{__dir__}/xml/encoding_normalizer"
    autoload :W3c, "#{__dir__}/xml/w3c"
    autoload :NamespaceResolutionStrategy,
             "#{__dir__}/xml/namespace_resolution_strategy"
    autoload :NamespaceInheritanceStrategy,
             "#{__dir__}/xml/namespace_inheritance_strategy"
    autoload :QualifiedInheritanceStrategy,
             "#{__dir__}/xml/qualified_inheritance_strategy"
    autoload :UnqualifiedInheritanceStrategy,
             "#{__dir__}/xml/unqualified_inheritance_strategy"
    autoload :DataModel, "#{__dir__}/xml/data_model"
    autoload :TransformationBuilder, "#{__dir__}/xml/transformation_builder"
    autoload :Element, "#{__dir__}/xml/element"
    autoload :ModelTransform, "#{__dir__}/xml/model_transform"
    autoload :TypeNamespaceResolver, "#{__dir__}/xml/type_namespace_resolver"
    autoload :NamespaceNeeds, "#{__dir__}/xml/namespace_needs"
    autoload :NamespaceUsage, "#{__dir__}/xml/namespace_usage"
    autoload :NamespaceDeclarationData,
             "#{__dir__}/xml/namespace_declaration_data"
    autoload :DeclarationHandler, "#{__dir__}/xml/declaration_handler"
    autoload :PolymorphicValueHandler,
             "#{__dir__}/xml/polymorphic_value_handler"
    autoload :AttributeNamespaceResolver,
             "#{__dir__}/xml/attribute_namespace_resolver"
    autoload :BlankNamespaceHandler, "#{__dir__}/xml/blank_namespace_handler"
    autoload :DeclarationPlanQuery, "#{__dir__}/xml/declaration_plan_query"
    autoload :DocTypeExtractor, "#{__dir__}/xml/doctype_extractor"
    autoload :InputNamespaceExtractor,
             "#{__dir__}/xml/input_namespace_extractor"
    autoload :NamespaceDeclarationBuilder,
             "#{__dir__}/xml/namespace_declaration_builder"
    autoload :ElementPrefixResolver, "#{__dir__}/xml/element_prefix_resolver"
    autoload :FormatChooser, "#{__dir__}/xml/format_chooser"
    autoload :HoistingAlgorithm, "#{__dir__}/xml/hoisting_algorithm"
    autoload :HoistingAlgorithm, "#{__dir__}/xml/hoisting_algorithm"
    autoload :NamespaceInheritanceResolver,
             "#{__dir__}/xml/namespace_inheritance_resolver"
    autoload :NamespaceScopeConfig, "#{__dir__}/xml/namespace_scope_config"
    autoload :Builder, "#{__dir__}/xml/builder"
    autoload :TypeNamespace, "#{__dir__}/xml/type_namespace"
    autoload :TransformationSupport, "#{__dir__}/xml/transformation_support"
    autoload :SharedDsl, "#{__dir__}/xml/shared_dsl"

    # Autoload adapter element classes (defined in subdirectories)
    autoload :NokogiriElement, "#{__dir__}/xml/nokogiri/element"
    autoload :OxElement, "#{__dir__}/xml/ox/element"

    # Autoload adapter module namespaces
    autoload :Nokogiri, "#{__dir__}/xml/nokogiri"
    autoload :Oga, "#{__dir__}/xml/oga"
    autoload :Rexml, "#{__dir__}/xml/rexml"
  end
end

# Register XML format with the model's format registry
Lutaml::Model::FormatRegistry.register(
  :xml,
  mapping_class: Lutaml::Xml::Mapping,
  adapter_class: nil,
  transformer: Lutaml::Xml::Transform,
)

# Include XML-specific serialization methods into Serialize::ClassMethods
Lutaml::Model::Serialize::ClassMethods.include(
  Lutaml::Xml::Serialization::FormatConversion,
)

# Auto-detect and set default XML adapter
if (adapter = Lutaml::Xml.detect_xml_adapter)
  Lutaml::Model::Config.xml_adapter_type = adapter
end
