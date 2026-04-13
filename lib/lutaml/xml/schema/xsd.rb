# frozen_string_literal: true

# NOTE: Do NOT require lutaml/model here. This file is autoloaded via
# Lutaml::Xml::Schema::Xsd, and requiring lutaml/model creates a circular
# dependency since lutaml/xml.rb requires lutaml/model. The adapter type
# is already set by lutaml/xml.rb at the end.

adapter = RUBY_ENGINE == "opal" ? :oga : :nokogiri
Lutaml::Model::Config.xml_adapter_type = adapter unless defined?(Lutaml::Model::Config.xml_adapter_type)

# Require the XsdNamespace class for XSD schema support
require_relative "xsd_namespace"

# Ensure parent module hierarchy exists before loading child files
# This allows child files to use compact module syntax (module Lutaml::Xml::Schema::Xsd)
module Lutaml
  module Xml
    module Schema
    end
  end
end

module Lutaml
  module Xml
    module Schema
      module Xsd
        # List of all XSD model classes that need to be autoloaded and registered.
        # This is used in parse() to ensure all types are registered before parsing.
        XSD_AUTOLOAD_CLASSES = %i[
          All Annotation Any AnyAttribute Appinfo Attribute AttributeGroup
          Choice ComplexContent ComplexType Documentation Element Enumeration
          ExtensionComplexContent ExtensionSimpleContent Field FractionDigits
          Glob Group Import Include Key Keyref Length List MaxExclusive
          MaxInclusive MaxLength MinExclusive MinInclusive MinLength
          Notation Pattern Redefine RestrictionComplexContent
          RestrictionSimpleContent RestrictionSimpleType Schema Selector
          Sequence SimpleContent SimpleType TotalDigits Union Unique WhiteSpace
          SchemaFileValidationResults
        ].freeze

        # Autoload all XSD model files (lazy loading)
        autoload :VERSION, "#{__dir__}/xsd/version"
        autoload :Error, "#{__dir__}/xsd/errors"
        autoload :SchemaValidator, "#{__dir__}/xsd/schema_validator"
        autoload :FileValidationResult, "#{__dir__}/xsd/file_validation_result"
        autoload :ValidationError, "#{__dir__}/xsd/validation_error"
        autoload :NamespaceUriRemapping, "#{__dir__}/xsd/namespace_uri_remapping"
        autoload :ValidationResult, "#{__dir__}/xsd/validation_result"
        autoload :Base, "#{__dir__}/xsd/base"
        autoload :SchemaLocationMapping, "#{__dir__}/xsd/schema_location_mapping"
        autoload :NamespaceMapping, "#{__dir__}/xsd/namespace_mapping"
        autoload :TypeResolutionResult, "#{__dir__}/xsd/type_resolution_result"
        autoload :TypeIndexEntry, "#{__dir__}/xsd/type_index_entry"
        autoload :SerializedSchema, "#{__dir__}/xsd/serialized_schema"
        autoload :SchemaNameResolver, "#{__dir__}/xsd/schema_name_resolver"
        autoload :All, "#{__dir__}/xsd/all"
        autoload :Annotation, "#{__dir__}/xsd/annotation"
        autoload :Any, "#{__dir__}/xsd/any"
        autoload :AnyAttribute, "#{__dir__}/xsd/any_attribute"
        autoload :Appinfo, "#{__dir__}/xsd/appinfo"
        autoload :Attribute, "#{__dir__}/xsd/attribute"
        autoload :AttributeGroup, "#{__dir__}/xsd/attribute_group"
        autoload :Choice, "#{__dir__}/xsd/choice"
        autoload :ComplexContent, "#{__dir__}/xsd/complex_content"
        autoload :ComplexType, "#{__dir__}/xsd/complex_type"
        autoload :Documentation, "#{__dir__}/xsd/documentation"
        autoload :Element, "#{__dir__}/xsd/element"
        autoload :Enumeration, "#{__dir__}/xsd/enumeration"
        autoload :ExtensionComplexContent, "#{__dir__}/xsd/extension_complex_content"
        autoload :ExtensionSimpleContent, "#{__dir__}/xsd/extension_simple_content"
        autoload :Field, "#{__dir__}/xsd/field"
        autoload :FractionDigits, "#{__dir__}/xsd/fraction_digits"
        autoload :Glob, "#{__dir__}/xsd/glob"
        autoload :Group, "#{__dir__}/xsd/group"
        autoload :Import, "#{__dir__}/xsd/import"
        autoload :Include, "#{__dir__}/xsd/include"
        autoload :Key, "#{__dir__}/xsd/key"
        autoload :Keyref, "#{__dir__}/xsd/keyref"
        autoload :Length, "#{__dir__}/xsd/length"
        autoload :List, "#{__dir__}/xsd/list"
        autoload :MaxExclusive, "#{__dir__}/xsd/max_exclusive"
        autoload :MaxInclusive, "#{__dir__}/xsd/max_inclusive"
        autoload :MaxLength, "#{__dir__}/xsd/max_length"
        autoload :MinExclusive, "#{__dir__}/xsd/min_exclusive"
        autoload :MinInclusive, "#{__dir__}/xsd/min_inclusive"
        autoload :MinLength, "#{__dir__}/xsd/min_length"
        autoload :Notation, "#{__dir__}/xsd/notation"
        autoload :Pattern, "#{__dir__}/xsd/pattern"
        autoload :Redefine, "#{__dir__}/xsd/redefine"
        autoload :RestrictionComplexContent, "#{__dir__}/xsd/restriction_complex_content"
        autoload :RestrictionSimpleContent, "#{__dir__}/xsd/restriction_simple_content"
        autoload :RestrictionSimpleType, "#{__dir__}/xsd/restriction_simple_type"
        autoload :Schema, "#{__dir__}/xsd/schema"
        autoload :Selector, "#{__dir__}/xsd/selector"
        autoload :Sequence, "#{__dir__}/xsd/sequence"
        autoload :SimpleContent, "#{__dir__}/xsd/simple_content"
        autoload :SimpleType, "#{__dir__}/xsd/simple_type"
        autoload :TotalDigits, "#{__dir__}/xsd/total_digits"
        autoload :Union, "#{__dir__}/xsd/union"
        autoload :Unique, "#{__dir__}/xsd/unique"
        autoload :WhiteSpace, "#{__dir__}/xsd/white_space"
        autoload :SchemaFileValidationResults, "#{__dir__}/xsd/schema_file_validation_results"

        module_function

        def register
          @register ||= Lutaml::Model::GlobalRegister.register(
            Lutaml::Model::Register.new(:xsd),
          )
        end

        def register_model(klass, id)
          register.register_model(klass, id: id)

          # Also register in default context so XSD types can be resolved
          # during XML parsing
          default_ctx = Lutaml::Model::GlobalContext.default_context
          unless default_ctx.registry.registered?(id)
            default_ctx.registry.register(id, klass)
          end
          # Also register by class name for string resolution
          klass_name = klass.to_s
          unless default_ctx.registry.registered?(klass_name.to_sym)
            default_ctx.registry.register(klass_name.to_sym, klass)
          end
        end

        def parse(xsd, location: nil, nested_schema: false, register: nil,
                  schema_mappings: nil, validate_schema: true)
          # Trigger autoloads for all XSD model classes to ensure they are
          # registered before parsing begins. This is necessary because
          # type resolution during parsing looks up classes in the register.
          # rubocop:disable Style/RedundantFetchOverride
          XSD_AUTOLOAD_CLASSES.each { |c| const_get(c) unless c == :VERSION }
          # rubocop:enable Style/RedundantFetchOverride

          # Validate XSD schema structure before parsing (unless disabled)
          if validate_schema && !nested_schema
            detected_version = SchemaValidator.detect_version(xsd)
            validator = SchemaValidator.new(version: detected_version)
            validator.validate(xsd)
          end

          register ||= self.register
          # Accumulate schemas across parse() calls. When parsing multiple
          # entrypoints (e.g., urbanFunction.xsd, urbanObject.xsd), each may
          # import shared schemas. The schema_by_location_or_instance method
          # checks processed_schemas first, so duplicates are avoided by reuse.

          Glob.schema_mappings = schema_mappings
          Glob.path_or_url(location)
          Schema.from_xml(xsd, register: register)
        end
      end
    end
  end
end
