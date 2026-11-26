# frozen_string_literal: true

require "lutaml/model"

# Root namespace for the LutaML libraries.
module Lutaml
  class Error < StandardError; end

  # Lutaml::Formatter and Lutaml::Layout live in the Lutaml top namespace
  # (not Lutaml::Lml) but their files are part of this gem. Declare the
  # autoloads here so first reference loads them lazily.
  autoload :Formatter, "lutaml/lml/formatter"
  autoload :Layout, "lutaml/lml/layout"

  # LML — the LutaML Model Language: parses the text DSL into domain
  # documents, compiles model definitions into Serializable classes,
  # and renders diagrams. See the entry-point contract under .parse /
  # .parse_document below.
  module Lml
    # Base error for LML failures; carries an optional Diagnostic.
    class Error < Lutaml::Error
      # Structured record for the failure, when one could be built.
      attr_reader :diagnostic

      def initialize(message = nil, diagnostic: nil)
        @diagnostic = diagnostic
        super(message)
      end
    end

    class ParsingError < Error; end
    class ImportError < Error; end
    class HydrationError < Error; end

    def self.compile(input, namespace: nil)
      ModelCompiler.new(namespace: namespace).compile(input)
    end

    # Entry-point contract:
    #
    #   parse           — Pipeline (preprocess, parse, transform, build)
    #                     followed by ViewResolution: view-import
    #                     expansion, show/hide filtering, and
    #                     association-label enrichment. Use for
    #                     documents consumed as diagrams or views.
    #   parse_document  — Pipeline only; the document keeps raw
    #                     collections and unresolved imports. Use for
    #                     machine processing (ModelCompiler, Validator)
    #                     where view semantics do not apply.
    #
    # Both return a Lutaml::Lml::Document.
    def self.parse(input)
      source = Source.wrap(input)
      document = Pipeline.call(source)
      ViewResolution.call(document, source.base_dir)
    end

    def self.parse_document(input)
      Pipeline.call(input)
    end

    # Top-level autoloads
    autoload :Parser, "lutaml/lml/parser"
    autoload :Pipeline, "lutaml/lml/pipeline"
    autoload :Preprocessor, "lutaml/lml/preprocessor"
    autoload :Source, "lutaml/lml/source"
    autoload :Transform, "lutaml/lml/transform"
    autoload :DataProcessor, "lutaml/lml/data_processor"
    autoload :DocumentBuilder, "lutaml/lml/document_builder"
    autoload :ModelCompiler, "lutaml/lml/model_compiler"
    autoload :ImportResolver, "lutaml/lml/import_resolver"
    autoload :ViewResolver, "lutaml/lml/view_resolver"
    autoload :Validator, "lutaml/lml/validator"
    autoload :ViewResolution, "lutaml/lml/view_resolution"
    autoload :EntityTypes, "lutaml/lml/entity_types"
    autoload :AssociationLabelResolver, "lutaml/lml/association_label_resolver"
    autoload :Executor, "lutaml/lml/executor"
    autoload :Lsp, "lutaml/lml/lsp"
    autoload :SymbolIndex, "lutaml/lml/symbol_index"
    autoload :YamlParser, "lutaml/lml/yaml_parser"
    autoload :HasAttributes, "lutaml/lml/has_attributes"
    autoload :Quoting, "lutaml/lml/quoting"
    autoload :Diagnostic, "lutaml/lml/diagnostic"
    autoload :SourcePosition, "lutaml/lml/source_position"
    autoload :Positioned, "lutaml/lml/positioned"
    autoload :VERSION, "lutaml/lml/version"

    # Type classes (Lutaml::Model::Type::Value subclasses, not models)
    autoload :LiteralValue, "lutaml/lml/literal_value"

    # Model classes (in Lutaml::Lml namespace, files in models/ directory)
    autoload :Action, "lutaml/lml/models/action"
    autoload :Association, "lutaml/lml/models/association"
    autoload :Cardinality, "lutaml/lml/models/cardinality"
    autoload :Collection, "lutaml/lml/models/collection"
    autoload :Constraint, "lutaml/lml/models/constraint"
    autoload :DataType, "lutaml/lml/models/data_type"
    autoload :Diagram, "lutaml/lml/models/diagram"
    autoload :Document, "lutaml/lml/models/document"
    autoload :Enum, "lutaml/lml/models/enum"
    autoload :Fidelity, "lutaml/lml/models/fidelity"
    autoload :Group, "lutaml/lml/models/group"
    autoload :Instance, "lutaml/lml/models/instance"
    autoload :InstanceCollection, "lutaml/lml/models/instance_collection"
    autoload :InstancesExport, "lutaml/lml/models/instances_export"
    autoload :InstancesImport, "lutaml/lml/models/instances_import"
    autoload :DerivedField, "lutaml/lml/models/derived_field"
    autoload :Mapping, "lutaml/lml/models/mapping"
    autoload :MemberField, "lutaml/lml/models/member_field"
    autoload :StringFormat, "lutaml/lml/models/string_format"
    autoload :Operation, "lutaml/lml/models/operation"
    autoload :OperationParameter, "lutaml/lml/models/operation_parameter"
    autoload :Package, "lutaml/lml/models/package"
    autoload :PrimitiveType, "lutaml/lml/models/primitive_type"
    autoload :Reference, "lutaml/lml/models/reference"
    autoload :TopElementAttribute, "lutaml/lml/models/top_element_attribute"
    autoload :UmlClass, "lutaml/lml/models/uml_class"
    autoload :Value, "lutaml/lml/models/value"
    autoload :ViewFilter, "lutaml/lml/models/view_filter"
    autoload :ViewImport, "lutaml/lml/models/view_import"
    autoload :MappingRule, "lutaml/lml/models/mapping_rule"
    autoload :Namespace, "lutaml/lml/models/namespace"
    autoload :SerializationMapping, "lutaml/lml/models/serialization_mapping"

    # Namespaces with their own autoloads
    autoload :Grammar, "lutaml/lml/grammar"
    autoload :Format, "lutaml/lml/format"
    autoload :Types, "lutaml/lml/types"
  end
end
