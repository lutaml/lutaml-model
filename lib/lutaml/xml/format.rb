# frozen_string_literal: true

# Lutaml::Xml - XML serialization module for LutaML
#
# This module provides XML-specific serialization functionality.
# It requires lutaml/model to be loaded first for base classes.

# Ensure base model is loaded

# XML requires moxml for parsing
require "moxml"

# Under Opal, moxml's autoloads don't fire (Opal ignores autoload).
# Pull in the eager-load boot that ships at lib/compat/opal/moxml_boot.rb
# so Moxml::Adapter::{Oga,Rexml} etc. are actually defined. Without
# this, `Config.adapter = :oga` later fails with
# `NameError: uninitialized constant Moxml::Adapter::Oga`.
if Lutaml::Model.opal?
  require "moxml_boot"
end

module Lutaml
  module Xml
    # Error module for XML-specific errors
    module Error
      autoload :XmlError, "#{__dir__}/error/xml_error"
      autoload :InvalidNamespaceError,
               "#{__dir__}/error/invalid_namespace_error"
      autoload :InvalidXsdTypeError,
               "#{__dir__}/error/invalid_xsd_type_error"
      autoload :XmlConfigurationError,
               "#{__dir__}/error/xml_configuration_error"
      autoload :NamespaceMismatchError,
               "#{__dir__}/error/namespace_mismatch_error"
      autoload :SchemaValidationError,
               "#{__dir__}/error/schema_validation_error"
    end

    # XML Configuration modules
    autoload :Configurable, "#{__dir__}/configurable"
    autoload :NamespaceTypeResolver, "#{__dir__}/namespace_type_resolver"

    # XML Type modules
    module Type
      autoload :ValueXmlMapping, "#{__dir__}/type/value_xml_mapping"
      autoload :Configurable, "#{__dir__}/type/configurable"
    end

    # XML Serialization modules
    autoload :Serialization, "#{__dir__}/serialization"

    # XML Schema modules
    autoload :Schema, "#{__dir__}/schema"

    # Detect available XML adapter.
    # Delegates to moxml, which is the authority on XML adapter
    # availability and platform constraints.
    #
    # @return [Symbol] adapter type name
    def self.detect_xml_adapter
      Moxml::Config.runtime_default_adapter
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
    autoload :Location, "#{__dir__}/schema_location"
    autoload :SchemaLocation, "#{__dir__}/schema_location"
    autoload :Namespace, "#{__dir__}/namespace"
    autoload :Mapping, "#{__dir__}/mapping"
    autoload :MappingRule, "#{__dir__}/mapping_rule"
    autoload :Listener, "#{__dir__}/listener"
    autoload :Document, "#{__dir__}/document"
    autoload :Transformation, "#{__dir__}/transformation"
    autoload :CustomMethodWrapper,
             "#{__dir__}/transformation/custom_method_wrapper"
    autoload :Transform, "#{__dir__}/transform"
    autoload :XsdValidator, "#{__dir__}/xsd_validator"
    autoload :Adapter, "#{__dir__}/adapter"
    autoload :XmlElement, "#{__dir__}/xml_element"
    autoload :AdapterElement, "#{__dir__}/adapter_element"
    autoload :XmlAttribute, "#{__dir__}/xml_attribute"
    autoload :Decisions, "#{__dir__}/decisions"
    autoload :DeclarationPlan, "#{__dir__}/declaration_plan"
    autoload :DeclarationPlanner, "#{__dir__}/declaration_planner"
    autoload :NamespaceCollector, "#{__dir__}/namespace_collector"
    autoload :NamespaceResolver, "#{__dir__}/namespace_resolver"
    autoload :NamespaceDeclaration, "#{__dir__}/namespace_declaration"
    autoload :NamespaceClassRegistry, "#{__dir__}/namespace_class_registry"
    autoload :BlankNamespace, "#{__dir__}/blank_namespace"
    autoload :EncodingNormalizer, "#{__dir__}/encoding_normalizer"
    autoload :W3c, "#{__dir__}/w3c"
    autoload :NamespaceResolutionStrategy,
             "#{__dir__}/namespace_resolution_strategy"
    autoload :NamespaceInheritanceStrategy,
             "#{__dir__}/namespace_inheritance_strategy"
    autoload :QualifiedInheritanceStrategy,
             "#{__dir__}/qualified_inheritance_strategy"
    autoload :UnqualifiedInheritanceStrategy,
             "#{__dir__}/unqualified_inheritance_strategy"
    autoload :DataModel, "#{__dir__}/data_model"
    autoload :TransformationBuilder, "#{__dir__}/transformation_builder"
    autoload :AdapterLoader, "#{__dir__}/adapter_loader"
    autoload :Element, "#{__dir__}/element"
    autoload :ModelTransform, "#{__dir__}/model_transform"
    autoload :TypeNamespaceResolver, "#{__dir__}/type_namespace_resolver"
    autoload :NamespaceNeeds, "#{__dir__}/namespace_needs"
    autoload :NamespaceUsage, "#{__dir__}/namespace_usage"
    autoload :NamespaceDeclarationData,
             "#{__dir__}/namespace_declaration_data"
    autoload :ParsedNamespaceDeclaration,
             "#{__dir__}/parsed_namespace_declaration"
    autoload :ParsedNamespaceSet, "#{__dir__}/parsed_namespace_set"
    autoload :DeclarationHandler, "#{__dir__}/declaration_handler"
    autoload :PolymorphicValueHandler,
             "#{__dir__}/polymorphic_value_handler"
    autoload :AttributeNamespaceResolver,
             "#{__dir__}/attribute_namespace_resolver"
    autoload :BlankNamespaceHandler, "#{__dir__}/blank_namespace_handler"
    autoload :DeclarationPlanQuery, "#{__dir__}/declaration_plan_query"
    autoload :DocTypeExtractor, "#{__dir__}/doctype_extractor"
    autoload :NamespaceDeclarationBuilder,
             "#{__dir__}/namespace_declaration_builder"
    autoload :ElementPrefixResolver, "#{__dir__}/element_prefix_resolver"
    autoload :FormatChooser, "#{__dir__}/format_chooser"
    autoload :HoistingAlgorithm, "#{__dir__}/hoisting_algorithm"
    autoload :NamespaceInheritanceResolver,
             "#{__dir__}/namespace_inheritance_resolver"
    autoload :NamespaceScopeConfig, "#{__dir__}/namespace_scope_config"
    autoload :Builder, "#{__dir__}/builder"
    autoload :TypeNamespace, "#{__dir__}/type_namespace"
    autoload :TransformationSupport, "#{__dir__}/transformation_support"
    autoload :SharedDsl, "#{__dir__}/shared_dsl"

    autoload :Oga, "#{__dir__}/oga"
    autoload :Rexml, "#{__dir__}/rexml"
    Lutaml::Model::RuntimeCompatibility.autoload_native(
      self,
      NokogiriElement: "#{__dir__}/nokogiri/element",
      Nokogiri: "#{__dir__}/nokogiri",
      Ox: "#{__dir__}/ox",
    )
  end
end

# Register XML format with the model's format registry
Lutaml::Model::FormatRegistry.register(
  :xml,
  mapping_class: Lutaml::Xml::Mapping,
  adapter_class: nil,
  transformer: Lutaml::Xml::Transform,
  adapter_loader: Lutaml::Xml::AdapterLoader,
  castable_type: Lutaml::Xml::XmlElement,
  key_value: false,
  error_types: %w[
    Moxml::ParseError
    Nokogiri::XML::SyntaxError
    Ox::ParseError
    REXML::ParseException
  ],
  adapter_options: if Lutaml::Model.opal?
                     # Both Oga (vendored opal-oga fork, pure-Ruby lexer)
                     # and REXML (bundled stdlib gem, pure Ruby) work
                     # under Opal. Oga is the default because moxml's CI
                     # verifies it most thoroughly; REXML is selectable
                     # for callers that prefer a stdlib-only stack.
                     {
                       available: %i[oga rexml],
                       default: :oga,
                     }
                   else
                     {
                       available: %i[nokogiri ox oga rexml],
                       default: :nokogiri,
                     }
                   end,
)

# Register XML transformation builder
Lutaml::Model::TransformationRegistry.register_builder(
  :xml, Lutaml::Xml::TransformationBuilder
)

# Extend Type::Value with XML configuration (namespace, xsd_type, xml block)
Lutaml::Model::Type::Value.include(Lutaml::Xml::Type::Configurable)

# Prepend XML-specific serialization hooks into Serialize::ClassMethods
# Uses prepend so XML's hook overrides (pre_deserialize_hook, validate_document, etc.)
# take priority over core's no-op defaults.
Lutaml::Model::Serialize::ClassMethods.prepend(
  Lutaml::Xml::Serialization::FormatConversion,
)

# Prepend XML-specific ModelImport overrides (root?, ensure_format_mapping_imports!, etc.)
Lutaml::Model::Serialize::ModelImport.prepend(
  Lutaml::Xml::Serialization::ModelImportExt,
)

# Prepend XML-specific instance methods (import_declaration_plan, validate_root_mapping!, etc.)
Lutaml::Model::Serialize.prepend(
  Lutaml::Xml::Serialization::InstanceMethods,
)

# Opal does not propagate methods prepended into an already-included module
# to classes that included it before the prepend. Serializable includes
# Serialize during model boot, so make the XML instance API available on the
# concrete base class as well.
#
# Anonymous model classes (Class.new { include Serialize }) extend
# Serialize::ClassMethods rather than inheriting from Serializable, so the
# ModelImportExt override (root?) must land on ClassMethods too. The other
# two (FormatConversion, InstanceMethods) are already prepended unconditionally
# above, so Opal's no-double-prepend rule means we don't repeat them here.
if Lutaml::Model.opal?
  Lutaml::Model::Serializable.singleton_class.prepend(
    Lutaml::Xml::Serialization::ModelImportExt,
  )

  Lutaml::Model::Serializable.prepend(
    Lutaml::Xml::Serialization::InstanceMethods,
  )

  Lutaml::Model::Serialize::ClassMethods.prepend(
    Lutaml::Xml::Serialization::ModelImportExt,
  )
end

# Register XML-specific attribute override warning names
Lutaml::Model::Attribute.format_specific_warn_names.push(:element_order,
                                                         :schema_location, :encoding, :doctype, :ordered?, :mixed?)

# Prepend XML-specific Collection overrides (unwrapped collection handling for XML)
require_relative "serialization/collection_ext"
Lutaml::Model::Collection.singleton_class.prepend(
  Lutaml::Xml::Serialization::CollectionExt,
)

# Register XML type serializers
require_relative "type/serializers"
Lutaml::Xml::Type::Serializers.register_all!

# Register XML schema methods
Lutaml::Model::Schema.register_method(:to_xsd) do |klass, options = {}|
  if Lutaml::Model.opal?
    raise NotImplementedError,
          "XSD schema generation is not available under Opal."
  end

  Lutaml::Xml::Schema::XsdSchema.generate(klass, options)
end

Lutaml::Model::Schema.register_method(:to_relaxng) do |klass, options = {}|
  if Lutaml::Model.opal?
    raise NotImplementedError,
          "RELAX NG schema generation requires Nokogiri, " \
          "which is not available under Opal."
  end

  Lutaml::Xml::Schema::RelaxngSchema.generate(klass, options)
end

Lutaml::Model::Schema.register_method(:from_xml) do |xml, options = {}|
  if Lutaml::Model.opal?
    raise NotImplementedError,
          "XML schema compilation is not available under Opal."
  end

  Lutaml::Model::Schema::XmlCompiler.to_models(xml, options)
end

Lutaml::Model::Schema.register_method(:from_relaxng) do |rng, options = {}|
  if Lutaml::Model::RuntimeCompatibility.opal?
    raise NotImplementedError,
          "RELAX NG schema compilation is not available under Opal."
  end

  Lutaml::Model::Schema::RngCompiler.to_models(rng, options)
end

Lutaml::Model::Schema.register_method(:from_rnc) do |rnc, options = {}|
  if Lutaml::Model::RuntimeCompatibility.opal?
    raise NotImplementedError,
          "RNC schema compilation is not available under Opal."
  end

  Lutaml::Model::Schema::RncCompiler.to_models(rnc, options)
end

# Register XML namespace registry with GlobalContext
Lutaml::Model::GlobalContext.register_format_registry(
  :xml, Lutaml::Xml::NamespaceClassRegistry.new
)

# Eagerly load W3C namespace definitions (has registration side effects)
require_relative "w3c"

# Auto-detection is now handled lazily by AdapterResolver on first use.
# No eager adapter selection at require time — libraries can configure
# their preferred adapter before any XML operations occur.

# Namespace identifier validation:
# - URIs (http://..., urn:...) are valid namespace names per W3C XML
#   Namespaces (RFC 3986). URNs are first-class identifiers (RFC 8141).
# - Non-URI identifiers (e.g., FPIs like "-//OASIS//...") are also
#   accepted for compatibility, though not spec-compliant.
# Use lenient mode to support FPIs and non-standard identifiers.
Moxml.configure do |config|
  config.namespace_validation_mode = :lenient
end
