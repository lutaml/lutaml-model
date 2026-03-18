# frozen_string_literal: true

require "moxml"

module Lutaml
  module Model
    # Autoloads for lazy loading - set up BEFORE any requires
    # These must be declared before files that reference these constants
    autoload :UninitializedClass, "#{__dir__}/model/uninitialized_class"
    autoload :Errors, "#{__dir__}/model/errors"
    autoload :Services, "#{__dir__}/model/services"
    autoload :VERSION, "#{__dir__}/model/version"
    autoload :Type, "#{__dir__}/model/type"
    autoload :TypeRegistry, "#{__dir__}/model/type_registry"
    autoload :TypeSubstitution, "#{__dir__}/model/type_substitution"
    autoload :TypeContext, "#{__dir__}/model/type_context"
    autoload :TypeResolver, "#{__dir__}/model/type_resolver"
    autoload :CachedTypeResolver, "#{__dir__}/model/cached_type_resolver"
    autoload :ContextRegistry, "#{__dir__}/model/context_registry"
    autoload :ImportRegistry, "#{__dir__}/model/import_registry"
    autoload :GlobalContext, "#{__dir__}/model/global_context"
    autoload :Utils, "#{__dir__}/model/utils"
    autoload :Serializable, "#{__dir__}/model/serializable"
    autoload :Error, "#{__dir__}/model/error"
    autoload :Constants, "#{__dir__}/model/constants"
    autoload :Config, "#{__dir__}/model/config"
    autoload :Configuration, "#{__dir__}/model/configuration"
    autoload :Instrumentation, "#{__dir__}/model/instrumentation"
    autoload :GlobalRegister, "#{__dir__}/model/global_register"
    autoload :Register, "#{__dir__}/model/register"
    autoload :Transformation, "#{__dir__}/model/transformation"
    autoload :CompiledRule, "#{__dir__}/model/compiled_rule"
    autoload :FormatRegistry, "#{__dir__}/model/format_registry"
    autoload :Collection, "#{__dir__}/model/collection"
    autoload :Store, "#{__dir__}/model/store"
    autoload :Schema, "#{__dir__}/model/schema"
    autoload :RenderPolicy, "#{__dir__}/model/render_policy"
    autoload :Liquid, "#{__dir__}/model/liquid"
    autoload :Liquefiable, "#{__dir__}/model/liquefiable"
    autoload :Mapping, "#{__dir__}/model/mapping/mapping"
    autoload :MappingRule, "#{__dir__}/model/mapping/mapping_rule"
    autoload :ModelMapping, "#{__dir__}/model/mapping/model_mapping"
    autoload :ModelMappingRule, "#{__dir__}/model/mapping/model_mapping_rule"
    autoload :TransformationBuilder, "#{__dir__}/model/transformation_builder"
    autoload :TransformationRegistry, "#{__dir__}/model/transformation_registry"
    autoload :ModelTransformer, "#{__dir__}/model/model_transformer"
    autoload :MappingHash, "#{__dir__}/model/mapping_hash"
    autoload :Transform, "#{__dir__}/model/transform"
    autoload :Serialize, "#{__dir__}/model/serialize"
    autoload :ComparableNil, "#{__dir__}/model/comparable_nil"
    autoload :ComparableModel, "#{__dir__}/model/comparable_model"
    autoload :CollectionHandler, "#{__dir__}/model/collection_handler"
    autoload :AttributeValidator, "#{__dir__}/model/attribute_validator"
    autoload :Attribute, "#{__dir__}/model/attribute"
    autoload :JsonAdapter, "#{__dir__}/model/json_adapter"
    autoload :SchemaLocation, "#{__dir__}/model/schema_location"
    autoload :Validation, "#{__dir__}/model/validation"
    autoload :Choice, "#{__dir__}/model/choice"
    autoload :Sequence, "#{__dir__}/model/sequence"
    autoload :ValueTransformer, "#{__dir__}/model/value_transformer"
    autoload :Registrable, "#{__dir__}/model/registrable"

    # Services classes (defined in services/ but under Lutaml::Model namespace)
    autoload :Logger, "#{__dir__}/model/services/logger"
    autoload :RuleValueExtractor,
             "#{__dir__}/model/services/rule_value_extractor"
    autoload :Transformer, "#{__dir__}/model/services/transformer"
    autoload :ImportTransformer, "#{__dir__}/model/services/transformer"
    autoload :ExportTransformer, "#{__dir__}/model/services/transformer"
    autoload :Validator, "#{__dir__}/model/services/validator"

    # Error classes (defined in error/ but under Lutaml::Model namespace)
    autoload :InvalidFormatError, "#{__dir__}/model/error/invalid_format_error"
    autoload :InvalidValueError, "#{__dir__}/model/error/invalid_value_error"
    autoload :InvalidAttributeTypeError,
             "#{__dir__}/model/error/invalid_attribute_type_error"
    autoload :LiquidNotEnabledError,
             "#{__dir__}/model/error/liquid_not_enabled_error"
    autoload :LiquidClassNotFoundError,
             "#{__dir__}/model/error/liquid_class_not_found_error"
    autoload :NoAttributesDefinedLiquidError,
             "#{__dir__}/model/error/no_attributes_defined_liquid_error"
    autoload :IncorrectMappingArgumentsError,
             "#{__dir__}/model/error/incorrect_mapping_argument_error"
    autoload :PatternNotMatchedError,
             "#{__dir__}/model/error/pattern_not_matched_error"
    autoload :UnknownAdapterTypeError,
             "#{__dir__}/model/error/unknown_adapter_type_error"
    autoload :FormatAdapterNotSpecifiedError,
             "#{__dir__}/model/error/format_adapter_not_specified_error"
    autoload :CollectionCountOutOfRangeError,
             "#{__dir__}/model/error/collection_count_out_of_range_error"
    autoload :ElementCountOutOfRangeError,
             "#{__dir__}/model/error/element_count_out_of_range_error"
    autoload :ValidationError, "#{__dir__}/model/error/validation_error"
    autoload :TypeNotEnabledError,
             "#{__dir__}/model/error/type_not_enabled_error"
    autoload :TypeError, "#{__dir__}/model/error/type_error"
    autoload :UnknownTypeError, "#{__dir__}/model/error/unknown_type_error"
    autoload :RequiredAttributeMissingError,
             "#{__dir__}/model/error/required_attribute_missing_error"
    autoload :MultipleMappingsError,
             "#{__dir__}/model/error/multiple_mappings_error"
    autoload :CollectionTrueMissingError,
             "#{__dir__}/model/error/collection_true_missing_error"
    autoload :IncorrectSequenceError,
             "#{__dir__}/model/error/incorrect_sequence_error"
    autoload :ChoiceUpperBoundError,
             "#{__dir__}/model/error/choice_upper_bound_error"
    autoload :NoRootMappingError, "#{__dir__}/model/error/no_root_mapping_error"
    autoload :ImportModelWithRootError,
             "#{__dir__}/model/error/import_model_with_root_error"
    autoload :InvalidChoiceRangeError,
             "#{__dir__}/model/error/invalid_choice_range_error"
    autoload :UnknownSequenceMappingError,
             "#{__dir__}/model/error/unknown_sequence_mapping_error"
    autoload :ChoiceLowerBoundError,
             "#{__dir__}/model/error/choice_lower_bound_error"
    autoload :NoMappingFoundError,
             "#{__dir__}/model/error/no_mapping_found_error"
    autoload :NoRootNamespaceError,
             "#{__dir__}/model/error/no_root_namespace_error"
    autoload :PolymorphicError, "#{__dir__}/model/error/polymorphic_error"
    autoload :ValidationFailedError,
             "#{__dir__}/model/error/validation_failed_error"
    autoload :InvalidAttributeNameError,
             "#{__dir__}/model/error/invalid_attribute_name_error"
    autoload :InvalidAttributeOptionsError,
             "#{__dir__}/model/error/invalid_attribute_options_error"
    autoload :UndefinedAttributeError,
             "#{__dir__}/model/error/undefined_attribute_error"
    autoload :SortingConfigurationConflictError,
             "#{__dir__}/model/error/sorting_configuration_conflict_error"
    autoload :TransformBlockNotDefinedError,
             "#{__dir__}/model/error/transform_block_not_defined_error"
    autoload :ReverseTransformBlockNotDefinedError,
             "#{__dir__}/model/error/reverse_transform_block_not_defined_error"
    autoload :MappingAttributeMissingError,
             "#{__dir__}/model/error/mapping_attribute_missing_error"
    autoload :MappingAttributeTypeError,
             "#{__dir__}/model/error/mapping_attribute_type_error"
    autoload :MappingAlreadyExistsError,
             "#{__dir__}/model/error/mapping_already_exists_error"
    autoload :ReverseTransformationDeclarationError,
             "#{__dir__}/model/error/reverse_transformation_declaration_error"
    autoload :UnresolvableTypeError,
             "#{__dir__}/model/error/unresolvable_type_error"

    # Error for passing incorrect model type
    #
    # @api private
    class IncorrectModelError < StandardError
    end

    class BaseModel < Serializable
    end

    # Module-level configuration
    #
    # @example
    #   Lutaml::Model.configure do |config|
    #     config.xml_adapter = :nokogiri
    #     config.json_adapter = :oj
    #   end
    #
    # @yield [Configuration] the configuration object
    # @return [Configuration] the configuration object
    def self.configure
      @configuration ||= Configuration.new
      yield @configuration if block_given?
      @configuration
    end

    # Get the current configuration
    #
    # @return [Configuration] the current configuration
    def self.configuration
      @configuration ||= Configuration.new
    end

    # Reset configuration to defaults
    #
    # @return [void]
    def self.reset_configuration!
      @configuration = nil
    end
  end
end

# Required files - these have side effects or are needed immediately
# Format files register DSL methods, so must be required
require "#{__dir__}/xml/data_model"
require "#{__dir__}/xml"
require "#{__dir__}/key_value"
require "#{__dir__}/model/json"
require "#{__dir__}/model/yaml"
require "#{__dir__}/model/toml"
require "#{__dir__}/model/hash"
require "#{__dir__}/model/jsonl"
require "#{__dir__}/model/yamls"
