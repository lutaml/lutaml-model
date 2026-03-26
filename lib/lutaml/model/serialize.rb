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
                               @register_records @xml_declaration_plan @xml_input_namespaces].freeze

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

      # Find the nearest superclass that has an XML mapping.
      #
      # Checks both @xml_mapping (set by Configurable#xml) and
      # mappings[:xml] (set by FormatConversion#process_mapping).
      #
      # @param klass [Class] The starting class
      # @return [Class, nil] The superclass with XML mapping or nil
      def self.superclass_with_xml_mapping(klass)
        return nil unless klass.is_a?(Class)

        parent = klass.superclass
        return nil unless parent < Lutaml::Model::Serializable

        # Check mappings[:xml] - this is where FormatConversion#process_mapping stores it
        parent_mapping = parent.mappings[:xml] if parent.respond_to?(:mappings)
        return parent if parent_mapping

        superclass_with_xml_mapping(parent)
      end

      def self.register_format_mapping_method(format)
        method_name = format == :hash ? :hsh : format

        ::Lutaml::Model::Serialize::ClassMethods.define_method(method_name) do |*args, &block|
          # If a mapping class is passed (e.g., xml SomeMapping),
          # inherit mappings from it directly.
          # This supports the reusable mapping class pattern.
          if format == :xml &&
              args.any? &&
              args.first.is_a?(Class) &&
              defined?(Lutaml::Xml::Mapping) &&
              args.first < Lutaml::Xml::Mapping
            mapping_class = args.first

            # Start with a copy of the parent class's XML mapping (if any).
            # This ensures child classes inherit their parent's mappings.
            parent_class = ::Lutaml::Model::Serialize.superclass_with_xml_mapping(self)
            parent_xml_mapping = if parent_class.respond_to?(:mappings)
                                   parent_class.mappings[:xml]
                                 end
            @xml_mapping = if parent_xml_mapping
                             parent_xml_mapping.deep_dup
                           else
                             Lutaml::Xml::Mapping.new
                           end

            # Get the parent mapping instance (DSL already evaluated via xml_mapping_instance)
            parent_mapping = if mapping_class.respond_to?(:xml_mapping_instance) &&
                mapping_class.xml_mapping_instance
                               mapping_class.xml_mapping_instance
                             else
                               mapping_class.new
                             end

            # --- Inherit namespaces ---
            existing_ns = @xml_mapping.namespace_scope || []
            parent_ns = parent_mapping.namespace_scope || []
            all_ns = (existing_ns + parent_ns).uniq
            @xml_mapping.namespace_scope(all_ns) if all_ns.any?
            # Also copy namespace_scope_config if present
            if parent_mapping.respond_to?(:namespace_scope_config) &&
                (parent_ns_config = parent_mapping.namespace_scope_config) &&
                parent_ns_config.any?
              existing_ns_config = @xml_mapping.namespace_scope_config || []
              merged_ns_config = (existing_ns_config + parent_ns_config).uniq
              @xml_mapping.instance_variable_set(:@namespace_scope_config,
                                                 merged_ns_config)
            end

            # --- Inherit element mappings ---
            parent_mapping.mapping_elements_hash.each do |key, rule|
              existing = @xml_mapping.mapping_elements_hash[key]
              if existing.nil?
                # No existing mapping - add parent's rule
                @xml_mapping.instance_variable_get(:@elements)[key] =
                  rule.deep_dup
              elsif existing.is_a?(Array) && rule.is_a?(Array)
                # Both arrays - merge, dedupe
                merged = existing + rule.reject do |r|
                  existing.any? do |e|
                    e.eql?(r)
                  end
                end
                @xml_mapping.instance_variable_get(:@elements)[key] = merged
              elsif existing.is_a?(Array)
                # Existing is array, parent has single
                unless existing.any? { |e| e.eql?(rule) }
                  existing << rule.deep_dup
                end
              elsif rule.is_a?(Array)
                # Parent has array, existing is single
                unless rule.any? { |r| r.eql?(existing) }
                  @xml_mapping.instance_variable_get(:@elements)[key] =
                    [existing, *rule]
                end
              elsif !existing.eql?(rule)
                # Different single rules - convert to polymorphic array
                @xml_mapping.instance_variable_get(:@elements)[key] =
                  [existing, rule.deep_dup]
              end
            end

            # --- Inherit attribute mappings ---
            parent_mapping.mapping_attributes_hash.each do |key, rule|
              existing = @xml_mapping.mapping_attributes_hash[key]
              if existing.nil?
                @xml_mapping.instance_variable_get(:@attributes)[key] =
                  rule.deep_dup
              elsif existing.is_a?(Array) && rule.is_a?(Array)
                merged = existing + rule.reject do |r|
                  existing.any? do |e|
                    e.eql?(r)
                  end
                end
                @xml_mapping.instance_variable_get(:@attributes)[key] = merged
              elsif existing.is_a?(Array)
                unless existing.any? { |e| e.eql?(rule) }
                  existing << rule.deep_dup
                end
              elsif rule.is_a?(Array)
                unless rule.any? { |r| r.eql?(existing) }
                  @xml_mapping.instance_variable_get(:@attributes)[key] =
                    [existing, *rule]
                end
              elsif !existing.eql?(rule)
                @xml_mapping.instance_variable_get(:@attributes)[key] =
                  [existing, rule.deep_dup]
              end
            end

            # --- Inherit element/root configuration ---
            if parent_mapping.element_name && !@xml_mapping.element_name
              @xml_mapping.element(parent_mapping.element_name)
            end

            if parent_mapping.namespace_class &&
                !@xml_mapping.instance_variable_get(:@namespace_class)
              @xml_mapping.namespace(parent_mapping.namespace_class)
            end

            if parent_mapping.namespace_param == :inherit &&
                !@xml_mapping.instance_variable_get(:@namespace_set)
              @xml_mapping.namespace(:inherit)
            end

            # Store parent reference
            @xml_mapping.inherit_from(mapping_class)

            # Evaluate any additional block
            @xml_mapping.instance_eval(&block) if block

            # CRITICAL: Also store in mappings[:xml] so the transformer can find it.
            # The mappings hash is initialized via initialize_attrs which deep-copies
            # from the parent. We must overwrite it with our merged mapping.
            mappings[:xml] = @xml_mapping

            @xml_mapping
          else
            process_mapping(format, &block)
          end
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
                    :lutaml_register, :lutaml_parent, :lutaml_root, :xml_declaration_plan
      attr_writer :ordered, :mixed

      def initialize(attrs = {}, options = {})
        @using_default = {}
        @lutaml_register = extract_register_id(attrs, options)
        return unless self.class.attributes(@lutaml_register)

        set_ordering(attrs)
        set_schema_location(attrs)
        set_doctype(attrs)
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
        resolver = Services::DefaultValueResolver.new(attr, lutaml_register, self)
        attr.validate_value!(value, lutaml_register, resolver)
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
        # NOTE: lutaml_register is always defined on Serialize instances
        options[:register] ||= lutaml_register if lutaml_register

        options[:parse_encoding] = encoding if encoding
        options[:doctype] = doctype if format == :xml && doctype

        # Pass XML declaration info for Issue #1: XML Declaration Preservation
        if format == :xml && @xml_declaration
          options[:xml_declaration] = @xml_declaration
        end

        # Pass input namespaces for Issue #3: Namespace Preservation
        if format == :xml && @xml_input_namespaces&.any?
          options[:input_namespaces] = @xml_input_namespaces
        end

        # Pass stored DeclarationPlan for format preservation
        # NOTE: xml_declaration_plan is always defined on Serialize instances
        if format == :xml && xml_declaration_plan
          options[:stored_xml_declaration_plan] = xml_declaration_plan
        end

        self.class.to(format, self, options)
      end

      private

      def validate_root_mapping!(format, options)
        return if format != :xml
        return if options[:collection] || self.class.root?(lutaml_register)

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
