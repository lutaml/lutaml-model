# frozen_string_literal: true

require "lutaml/model"

adapter = RUBY_ENGINE == "opal" ? :oga : :nokogiri
Lutaml::Model::Config.xml_adapter_type = adapter

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
          # Validate XSD schema structure before parsing (unless disabled)
          if validate_schema && !nested_schema
            detected_version = SchemaValidator.detect_version(xsd)
            validator = SchemaValidator.new(version: detected_version)
            validator.validate(xsd)
          end

          register ||= self.register
          Schema.reset_processed_schemas unless nested_schema

          Glob.schema_mappings = schema_mappings
          Glob.path_or_url(location)
          Schema.from_xml(xsd, register: register)
        end
      end
    end
  end
end

# Require all XSD model files
require_relative "xsd/version"
require_relative "xsd/errors"
require_relative "xsd/schema_validator"
require_relative "xsd/file_validation_result"
require_relative "xsd/validation_error"
require_relative "xsd/namespace_uri_remapping"
require_relative "xsd/validation_result"
require_relative "xsd/base"
require_relative "xsd/schema_location_mapping"
require_relative "xsd/namespace_mapping"
require_relative "xsd/type_resolution_result"
require_relative "xsd/type_index_entry"
require_relative "xsd/serialized_schema"
require_relative "xsd/schema_name_resolver"
require_relative "xsd/all"
require_relative "xsd/annotation"
require_relative "xsd/any"
require_relative "xsd/any_attribute"
require_relative "xsd/appinfo"
require_relative "xsd/attribute"
require_relative "xsd/attribute_group"
require_relative "xsd/choice"
require_relative "xsd/complex_content"
require_relative "xsd/complex_type"
require_relative "xsd/documentation"
require_relative "xsd/element"
require_relative "xsd/enumeration"
require_relative "xsd/extension_complex_content"
require_relative "xsd/extension_simple_content"
require_relative "xsd/field"
require_relative "xsd/fraction_digits"
require_relative "xsd/glob"
require_relative "xsd/group"
require_relative "xsd/import"
require_relative "xsd/include"
require_relative "xsd/key"
require_relative "xsd/keyref"
require_relative "xsd/length"
require_relative "xsd/list"
require_relative "xsd/max_exclusive"
require_relative "xsd/max_inclusive"
require_relative "xsd/max_length"
require_relative "xsd/min_exclusive"
require_relative "xsd/min_inclusive"
require_relative "xsd/min_length"
require_relative "xsd/notation"
require_relative "xsd/pattern"
require_relative "xsd/redefine"
require_relative "xsd/restriction_complex_content"
require_relative "xsd/restriction_simple_content"
require_relative "xsd/restriction_simple_type"
require_relative "xsd/schema"
require_relative "xsd/selector"
require_relative "xsd/sequence"
require_relative "xsd/simple_content"
require_relative "xsd/simple_type"
require_relative "xsd/total_digits"
require_relative "xsd/union"
require_relative "xsd/unique"
require_relative "xsd/white_space"
require_relative "xsd/schema_file_validation_results"
