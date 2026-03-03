# frozen_string_literal: true

require "active_support/inflector"

module Lutaml
  module Model
    module Serialize
      # Autoload subdirectory modules
      autoload :Initialization, "#{__dir__}/serialize/initialization"
      autoload :AttributeDefinition, "#{__dir__}/serialize/attribute_definition"
      autoload :EnumHandling, "#{__dir__}/serialize/enum_handling"
      autoload :ModelImport, "#{__dir__}/serialize/model_import"
      autoload :FormatConversion, "#{__dir__}/serialize/format_conversion"
      autoload :ValueMapping, "#{__dir__}/serialize/value_mapping"
      autoload :TransformationBuilder,
               "#{__dir__}/serialize/transformation_builder"

      include ComparableModel
      include Validation
      include Lutaml::Model::Liquefiable
      include Lutaml::Model::Registrable

      # Performance: Pre-computed default value map to avoid per-call allocations
      DEFAULT_VALUE_MAP = {
        omitted: :nil,
        nil: :nil,
        empty: :empty,
      }.freeze

      INTERNAL_ATTRIBUTES = %i[@using_default @__register @__parent
                               @__root].freeze

      def self.included(base)
        base.extend(ClassMethods)
        base.initialize_attrs(base)
      end

      module ClassMethods
        include Lutaml::Model::Liquefiable::ClassMethods
        include Serialize::Initialization
        include Serialize::AttributeDefinition
        include Serialize::EnumHandling
        include Serialize::ModelImport
        include Serialize::FormatConversion
        include Serialize::ValueMapping
        include Serialize::TransformationBuilder

        attr_accessor :choice_attributes, :mappings
      end

      def self.register_format_mapping_method(format)
        method_name = format == :hash ? :hsh : format

        ::Lutaml::Model::Serialize::ClassMethods.define_method(method_name) do |&block|
          process_mapping(format, &block)
        end
      end

      def self.register_from_format_method(format)
        ClassMethods.define_method(:"from_#{format}") do |data, options = {}|
          from(format, data, options)
        end

        ClassMethods.define_method(:"of_#{format}") do |doc, options = {}|
          of(format, doc, options)
        end
      end

      def self.register_to_format_method(format)
        ClassMethods.define_method(:"to_#{format}") do |instance, options = {}|
          to(format, instance, options)
        end

        ClassMethods.define_method(:"as_#{format}") do |instance, options = {}|
          as(format, instance, options)
        end

        define_method(:"to_#{format}") do |options = {}|
          to_format(format, options)
        end
      end

      attr_accessor :element_order, :schema_location, :encoding, :doctype,
                    :__register, :__parent, :__root, :__input_declaration_plan
      attr_writer :ordered, :mixed

      def initialize(attrs = {}, options = {})
        @using_default = {}
        @__register = extract_register_id(attrs, options)
        return unless self.class.attributes(__register)

        set_ordering(attrs)
        set_schema_location(attrs)
        set_doctype(attrs)
        initialize_attributes(attrs, options)

        register_in_reference_store
      end

      def extract_register_id(attrs, options)
        register = attrs&.dig(:__register) || options&.dig(:register)
        self.class.extract_register_id(register)
      end

      def value_map(options)
        # Fast path: return default map if no custom options
        return DEFAULT_VALUE_MAP if options.equal?(Type::Value::EMPTY_OPTIONS)
        return DEFAULT_VALUE_MAP if options.empty?

        # Slow path: merge with custom options
        {
          omitted: options[:omitted] || :nil,
          nil: options[:nil] || :nil,
          empty: options[:empty] || :empty,
        }
      end

      def attr_value(attrs, name, attribute)
        value = Utils.fetch_str_or_sym(attrs, name,
                                       attribute.default(__register))
        attribute.cast_value(value, __register)
      end

      def using_default_for(attribute_name)
        @using_default[attribute_name] = true
      end

      def value_set_for(attribute_name)
        @using_default[attribute_name] = false
      end

      def using_default?(attribute_name)
        @using_default[attribute_name]
      end

      def method_missing(method_name, *args)
        if method_name.to_s.end_with?("=") && attribute_exist?(method_name)
          define_singleton_method(method_name) do |value|
            instance_variable_set(:"@#{method_name.to_s.chomp('=')}", value)
          end
          send(method_name, *args)
        else
          super
        end
      end

      def respond_to_missing?(method_name, include_private = false)
        (method_name.to_s.end_with?("=") && attribute_exist?(method_name)) ||
          super
      end

      def attribute_exist?(name)
        name = name.to_s.chomp("=").to_sym if name.end_with?("=")

        self.class.attributes.key?(name)
      end

      def validate_attribute!(attr_name)
        attr = self.class.attributes[attr_name]
        value = instance_variable_get(:"@#{attr_name}")
        attr.validate_value!(value)
      end

      def ordered?
        !!@ordered
      end

      def mixed?
        !!@mixed
      end

      def key_exist?(hash, key)
        hash.key?(key.to_sym) || hash.key?(key.to_s)
      end

      def key_value(hash, key)
        hash[key.to_sym] || hash[key.to_s]
      end

      def pretty_print_instance_variables
        reference_attributes = instance_variables.select do |var|
          var.to_s.end_with?("_ref")
        end
        (instance_variables - INTERNAL_ATTRIBUTES - reference_attributes).sort
      end

      def to_yaml_hash
        self.class.as_yaml(self)
      end

      def to_format(format, options = {})
        validate_root_mapping!(format, options)

        # Pass instance's __register if not explicitly provided
        # NOTE: __register is always defined on Serialize instances
        options[:register] ||= __register if __register

        options[:parse_encoding] = encoding if encoding
        options[:doctype] = doctype if format == :xml && doctype

        # Pass XML declaration info for Issue #1: XML Declaration Preservation
        if format == :xml && @xml_declaration
          options[:xml_declaration] = @xml_declaration
        end

        # Pass input namespaces for Issue #3: Namespace Preservation
        if format == :xml && @__input_namespaces&.any?
          options[:input_namespaces] = @__input_namespaces
        end

        # Pass stored DeclarationPlan for format preservation
        # NOTE: __input_declaration_plan is always defined on Serialize instances
        if format == :xml && __input_declaration_plan
          options[:__stored_plan] = __input_declaration_plan
        end

        self.class.to(format, self, options)
      end

      private

      def validate_root_mapping!(format, options)
        return if format != :xml
        return if options[:collection] || self.class.root?(__register)

        raise Lutaml::Model::NoRootMappingError.new(self.class)
      end

      def set_ordering(attrs)
        return unless attrs.respond_to?(:ordered?)

        @ordered = attrs.ordered?
        @element_order = attrs.item_order
      end

      def set_schema_location(attrs)
        return unless attrs.key?(:schema_location)

        self.schema_location = attrs[:schema_location]
      end

      def set_doctype(attrs)
        return unless attrs.key?(:doctype)

        self.doctype = attrs[:doctype]
      end

      def initialize_attributes(attrs, options = {})
        # Performance: Get value_map once for all attributes
        vmap = value_map(options)

        self.class.attributes(__register).each do |name, attr|
          next if attr.derived?

          value = determine_value(attrs, name, attr)
          default = using_default?(name)
          value = self.class.apply_value_map(value, vmap, attr)
          # Performance: Only call ensure_utf8 for string values
          value = self.class.ensure_utf8(value) if value.is_a?(::String)
          public_send(:"#{name}=", value)
          using_default_for(name) if default
        end
      end

      def determine_value(attrs, name, attr)
        # Performance: Single-pass key lookup with value retrieval
        # Check symbol key first (most common), then string key
        if attrs.key?(name)
          return attr.cast_value(attrs[name], __register)
        elsif attrs.key?(name.to_s)
          return attr.cast_value(attrs[name.to_s], __register)
        end

        if attr.default_set?(__register)
          using_default_for(name)
          attr.default(__register)
        else
          Lutaml::Model::UninitializedClass.instance
        end
      end

      def register_in_reference_store
        Lutaml::Model::Store.register(self)
      end

      def resolve_reference_key(ref)
        return nil if ref.nil?

        return ref.map { |r| resolve_reference_key(r) } if ref.is_a?(Array)

        ref.is_a?(Type::Reference) ? ref.key : ref
      end

      def resolve_reference_value(ref)
        return nil if ref.nil?

        return ref.map { |r| resolve_reference_value(r) } if ref.is_a?(Array)

        ref.is_a?(Type::Reference) ? ref.object : ref
      end
    end
  end
end
