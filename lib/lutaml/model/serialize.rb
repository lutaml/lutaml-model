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

      INTERNAL_ATTRIBUTES = %i[@using_default @lutaml_register @lutaml_parent @lutaml_root
                               @register_records].freeze

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

        attr_accessor :choice_attributes, :mappings, :register_records
      end

      def self.register_format_mapping_method(format)
        method_name = format == :hash ? :hsh : format

        ::Lutaml::Model::Serialize::ClassMethods.define_method(method_name) do |*args, &block|
          process_mapping(format, *args, &block)
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

      attr_accessor :lutaml_register, :lutaml_parent, :lutaml_root

      def initialize(attrs = {}, options = {})
        @using_default = {}
        @lutaml_register = extract_register_id(attrs, options)
        return unless self.class.attributes(@lutaml_register)

        initialize_attributes(attrs, options)
        define_singleton_attribute_methods

        register_in_reference_store
      end

      def extract_register_id(attrs, options)
        register = attrs&.dig(:lutaml_register) || options&.dig(:register)
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
                                       attribute.default(lutaml_register, self))
        attribute.cast_value(value, lutaml_register)
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

      def method_missing(method_name, *)
        if method_name.to_s.end_with?("=") && attribute_exist?(method_name)
          define_singleton_method(method_name) do |value|
            instance_variable_set(:"@#{method_name.to_s.chomp('=')}", value)
          end
          send(method_name, *)
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

        self.class.attributes(lutaml_register).key?(name)
      end

      def validate_attribute!(attr_name)
        attr = self.class.attributes[attr_name]
        value = instance_variable_get(:"@#{attr_name}")
        resolver = Services::DefaultValueResolver.new(attr, lutaml_register,
                                                      self)
        attr.validate_value!(value, lutaml_register, resolver)
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

      # Serialize to a specific format
      #
      # @param format [Symbol] The format to serialize to (:xml, :json, :yaml, :toml, :hash)
      # @param options [Hash] Serialization options
      # @option options [Symbol, String, Boolean] :prefix XML namespace prefix control
      #   - nil (default): Preserve input format during round-trip
      #   - true: Force prefix format using namespace's prefix_default
      #   - :default: Force default namespace format (no prefix on element)
      #   - String: Use custom prefix string (e.g., 'custom')
      #   For round-trip fidelity, the original namespace URI (alias or canonical)
      #   is always preserved when available, regardless of this option.
      def to_format(format, options = {})
        # Hook for format-specific validation (e.g., XML root mapping check)
        validate_root_mapping!(format, options)

        # Handle prefix option for XML (converts to use_prefix for transformation phase)
        # This must happen BEFORE self.class.to is called so transformation sees use_prefix
        if format == :xml && options.key?(:prefix)
          prefix_option = options[:prefix]
          case prefix_option
          when true
            options[:use_prefix] = true
          when String
            options[:use_prefix] = prefix_option
          when false
            options[:use_prefix] = false
          end
          options.delete(:prefix)
        end

        # Pass instance's lutaml_register if not explicitly provided
        options[:register] ||= lutaml_register if lutaml_register

        # Hook for format-specific options preparation
        # XML overrides to handle prefix, doctype, declaration, namespaces
        prepare_instance_format_options(format, options)

        self.class.to(format, self, options)
      end

      # Hook for format-specific instance-level options preparation.
      # XML overrides via InstanceMethods prepend.
      #
      # @param _format [Symbol] The format
      # @param _options [Hash] Options hash (modified in place)
      def prepare_instance_format_options(_format, _options)
        # No-op by default
      end

      # Hook for format-specific root mapping validation.
      # XML overrides via InstanceMethods prepend.
      #
      # @param _format [Symbol] The format
      # @param _options [Hash] Options hash
      def validate_root_mapping!(_format, _options)
        # No-op by default
      end

      private

      # Define attribute accessor methods on the instance's singleton class
      # for attributes that are register-specific (not defined at class level).
      def define_singleton_attribute_methods
        return if lutaml_register == :default

        # Access class-level register_records via self.class to avoid
        # triggering ensure_imports! which would resolve types in wrong context
        reg_records = self.class.register_records
        return unless reg_records

        reg_record = reg_records[lutaml_register]
        return unless reg_record

        reg_record_attrs = reg_record[:attributes] || {}
        # @attributes contains default register's class-level attributes
        default_attrs = self.class.instance_variable_get(:@attributes) || {}

        reg_record_attrs.each do |name, attr|
          # Skip if already defined at class level (from default register)
          next if default_attrs.key?(name)

          # Define getter on singleton class
          singleton_class.define_method(name) do
            instance_variable_get(:"@#{name}")
          end

          # Define setter on singleton class with type casting
          singleton_class.define_method(:"#{name}=") do |value|
            value = attr.cast_value(value, lutaml_register)
            instance_variable_set(:"@#{name}", value)
          end
        end
      end

      def initialize_attributes(attrs, options = {})
        # Performance: Get value_map once for all attributes
        vmap = value_map(options)

        self.class.attributes(lutaml_register).each do |name, attr|
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
        if attrs.key?(name) || attrs.key?(name.to_s)
          return attr_value(attrs, name, attr)
        end

        if attr.default_set?(lutaml_register, self)
          using_default_for(name)
          attr.default(lutaml_register, self)
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
