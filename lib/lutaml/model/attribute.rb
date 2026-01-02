module Lutaml
  module Model
    class Attribute
      attr_reader :name, :options

      ALLOWED_OPTIONS = %i[
        raw
        default
        delegate
        collection
        values
        pattern
        transform
        choice
        sequence
        method
        method_name
        polymorphic
        polymorphic_class
        initialize_empty
        validations
        required
        ref_model_class
        ref_key_attribute
        xsd_type
      ].freeze

      MODEL_STRINGS = [
        Lutaml::Model::Type::String,
        "String",
        :string,
      ].freeze

      # Safe methods than can be overriden without any crashing
      ALLOW_OVERRIDING = %i[
        display
        validate
        hash
        itself
        taint
        untaint
        trust
        untrust
        methods
        instance_variables
        tap
        extend
        freeze
        encoding
        method
        object_id
      ].freeze

      def self.cast_type!(type)
        case type
        when Symbol then cast_from_symbol!(type)
        when String then cast_from_string!(type)
        when Class then type
        else
          raise ArgumentError, "Unknown Lutaml::Model::Type: #{type}"
        end
      end

      def self.cast_from_symbol!(type)
        Type.lookup(type)
      rescue UnknownTypeError
        raise ArgumentError, "Unknown Lutaml::Model::Type: #{type}"
      end

      def self.cast_from_string!(type)
        Type.const_get(type)
      rescue NameError
        raise ArgumentError, "Unknown Lutaml::Model::Type: #{type}"
      end

      def initialize(name, type, options = {})
        validate_name!(
          name, reserved_methods: Lutaml::Model::Serializable.instance_methods
        )

        @name = name
        @options = options

        validate_presence!(type)
        @type = type
        process_options!
      end

      def type(register_id = nil)
        return if unresolved_type.nil?

        register_id ||= Lutaml::Model::Config.default_register
        register = Lutaml::Model::GlobalRegister.lookup(register_id)
        register.get_class_without_register(unresolved_type)
      end

      def unresolved_type
        @type
      end

      def polymorphic?
        @options[:polymorphic_class]
      end

      def derived?
        !method_name.nil?
      end

      def delegate
        @options[:delegate]
      end

      def transform
        @options[:transform] || {}
      end

      def method_name
        @options[:method_name]
      end

      def initialize_empty?
        @options[:initialize_empty]
      end

      def validations
        @options[:validations]
      end

      def cast_type!(type)
        self.class.cast_type!(type)
      end

      def cast_value(value, register)
        return cast_element(value, register) unless collection_instance?(value)

        build_collection(value.map { |v| cast_element(v, register) })
      end

      def required_value_set?(value)
        return true unless options[:required]
        return false if value.nil?
        return false if value.respond_to?(:empty?) && value.empty?

        true
      end

      def cast_element(value, register)
        resolved_type = type(register)
        return resolved_type.new(value) if value.is_a?(::Hash) && !hash_type?

        # Special handling for Reference types - pass the metadata
        if unresolved_type == Lutaml::Model::Type::Reference
          return resolved_type.cast_with_metadata(value,
                                                  @options[:ref_model_class], @options[:ref_key_attribute])
        end

        validate_attr_type!(resolved_type)

        resolved_type.cast(value)
      end

      def hash_type?
        type == Lutaml::Model::Type::Hash
      end

      def setter
        :"#{@name}="
      end

      def collection
        @options[:collection]
      end

      def collection?
        collection || false
      end

      def singular?
        !collection?
      end

      def collection_class
        return Array unless custom_collection?

        collection
      end

      def collection_instance?(value)
        value.is_a?(collection_class)
      end

      def build_collection(*args)
        collection_class.new(args.flatten)
      end

      def raw?
        @raw
      end

      def enum?
        !enum_values.empty?
      end

      def pattern
        options[:pattern]
      end

      def enum_values
        @options.key?(:values) ? @options[:values] : []
      end

      def transform_import_method
        transform[:import]
      end

      def transform_export_method
        transform[:export]
      end

      def valid_value!(value)
        return true if value.nil? && singular?
        return true unless enum?
        return true if Utils.uninitialized?(value)

        unless valid_value?(value)
          raise Lutaml::Model::InvalidValueError.new(name, value, enum_values)
        end

        true
      end

      def valid_value?(value)
        return true unless options[:values]

        options[:values].include?(value)
      end

      def valid_pattern!(value, resolved_type)
        return true unless resolved_type == Lutaml::Model::Type::String
        return true unless pattern

        unless pattern.match?(value)
          raise Lutaml::Model::PatternNotMatchedError.new(name, pattern, value)
        end

        true
      end

      # Check if the value to be assigned is valid for the attribute
      #
      # Currently there are 2 validations
      #   1. Value should be from the values list if they are defined
      #      e.g values: ["foo", "bar"] is set then any other value for this
      #          attribute will raise `Lutaml::Model::InvalidValueError`
      #
      #   2. Value count should be between the collection range if defined
      #      e.g if collection: 0..5 is set then the value greater then 5
      #          will raise `Lutaml::Model::CollectionCountOutOfRangeError`
      def validate_value!(value, register, resolver = nil)
        # Use the default value if the value is nil
        validate_required!(value)

        value = resolver&.default if value.nil?
        resolved_type = type(register)

        valid_value!(value) &&
          valid_collection!(value, self) &&
          valid_pattern!(value, resolved_type) &&
          validate_polymorphic!(value, resolved_type) &&
          execute_validations!(value)
      end

      # execute custom validations on the attribute value
      # i.e presence: true, numericality: true, etc
      def execute_validations!(value)
        return true if Utils.blank?(value)

        memoization_container = {}
        errors = Lutaml::Model::Validator.call(value, validations,
                                               memoization_container)

        return if errors.empty?

        raise Lutaml::Model::ValidationFailedError.new(errors)
      end

      def validate_polymorphic(value, resolved_type)
        if value.is_a?(Array)
          return value.all? do |v|
            validate_polymorphic!(v, resolved_type)
          end
        end
        return true unless options[:polymorphic]

        valid_polymorphic_type?(value, resolved_type)
      end

      def validate_polymorphic!(value, resolved_type)
        return true if validate_polymorphic(value, resolved_type)

        raise Lutaml::Model::PolymorphicError.new(value, options, resolved_type)
      end

      def validate_collection_range
        range = @options[:collection]
        return if range == true
        return if custom_collection?

        unless range.is_a?(Range)
          raise ArgumentError, "Invalid collection range: #{range}"
        end

        validate_range!(range)
      end

      def validate_range!(range)
        if range.begin.nil?
          raise ArgumentError,
                "Invalid collection range: #{range}. Begin must be specified."
        end

        if range.begin.negative?
          raise ArgumentError,
                "Invalid collection range: #{range}. " \
                "Begin must be non-negative."
        end

        if range.end && range.end < range.begin
          raise ArgumentError,
                "Invalid collection range: #{range}. " \
                "End must be greater than or equal to begin."
        end
      end

      def valid_collection!(value, caller)
        if collection_instance?(value) && !collection?
          raise Lutaml::Model::CollectionTrueMissingError.new(name,
                                                              caller)
        end

        return true unless collection?

        # Allow any value for unbounded collections
        return true if collection == true

        unless (Utils.uninitialized?(value) && resolved_collection.min.zero?) || collection_instance?(value)
          raise Lutaml::Model::CollectionCountOutOfRangeError.new(
            name,
            value,
            collection,
          )
        end

        return true unless resolved_collection.is_a?(Range)

        if resolved_collection.is_a?(Range) && resolved_collection.end.infinite?
          if value.size < resolved_collection.begin
            raise Lutaml::Model::CollectionCountOutOfRangeError.new(
              name,
              value,
              collection,
            )
          end
        elsif resolved_collection.is_a?(Range) && !resolved_collection.cover?(value.size)
          raise Lutaml::Model::CollectionCountOutOfRangeError.new(
            name,
            value,
            collection,
          )
        end
      end

      def serialize(value, format, register, options = {})
        value ||= build_collection if collection? && initialize_empty?
        return value if value.nil? || Utils.uninitialized?(value)

        resolved_type = options[:resolved_type] || type(register)
        serialize_options = options.merge(resolved_type: resolved_type)
        value = reference_key(value) if unresolved_type == Lutaml::Model::Type::Reference
        if collection_instance?(value)
          return serialize_array(value, format, register,
                                 serialize_options)
        end
        if resolved_type <= Serialize
          return serialize_model(value, format, register,
                                 options)
        end

        serialize_value(value, format, resolved_type)
      end

      def reference_key(value)
        return nil unless value
        return value.map { |item| reference_key(item) } if value.is_a?(Array)

        return value.public_send(@options[:ref_key_attribute]) if model_instance?(value)

        value
      end

      def model_instance?(value)
        return false unless value.respond_to?(:class)
        return false unless @options[:ref_model_class]

        value.class.name == @options[:ref_model_class]
      end

      def cast(value, format, register, options = {})
        resolved_type = options[:resolved_type] || type(register)
        if collection_instance?(value) || value.is_a?(Array)
          return build_collection(value.map do |v|
            cast(v, format, register,
                 options.merge(resolved_type: resolved_type, converted: true))
          end)
        end

        return value if already_serialized?(resolved_type, value)

        klass = resolve_polymorphic_class(resolved_type, value, options)
        if can_serialize?(klass, value, format, options)
          klass.apply_mappings(value, format, options.merge(register: register))
        elsif needs_conversion?(klass, value)
          klass.send(:"from_#{format}", value)
        else
          # No need to use register#get_class,
          # can_serialize? method already checks if type is Serializable or not.
          Type.lookup(klass).cast(value)
        end
      end

      def serializable?(register)
        type(register) <= Serialize
      end

      def resolved_collection
        return unless collection?

        collection.is_a?(Range) ? validated_range_object : 0..Float::INFINITY
      end

      def sequenced_appearance_count(element_order, mapped_name, current_index)
        elements = element_order[current_index..]
        element_count = elements.take_while do |element|
          element == mapped_name
        end.count
        return element_count if element_count.between?(*resolved_collection.minmax)

        raise Lutaml::Model::ElementCountOutOfRangeError.new(
          mapped_name,
          element_count,
          collection,
        )
      end

      def validate_choice_content!(elements)
        return elements.count unless resolved_collection
        return 1 if elements.count.between?(*resolved_collection.minmax)

        elements.each_slice(resolved_collection.max).count
      end

      def min_collection_zero?
        collection? && resolved_collection.min.zero?
      end

      def choice
        @options[:choice]
      end

      def process_options!
        validate_options!(@options)
        @raw = !!@options[:raw]
        @validations = @options[:validations]
        set_default_for_collection if collection?
      end

      def deep_dup
        self.class.new(name, unresolved_type, Utils.deep_dup(options))
      end

      # Get namespace class from Type::Value or Model class
      #
      # @param register [Symbol, nil] register ID for type resolution
      # @return [Class, nil] XmlNamespace class if type has namespace
      def type_namespace_class(register = nil)
        resolved_type = type(register)
        return nil unless resolved_type

        # Check if type responds to xml_namespace (Type::Value classes)
        return resolved_type.xml_namespace if resolved_type.respond_to?(:xml_namespace)

        # Check if type is a Serializable model with namespace in XML mappings
        if resolved_type <= Lutaml::Model::Serialize
          xml_mapping = resolved_type.mappings_for(:xml, register)
          if xml_mapping&.namespace_uri
            # Create an anonymous XmlNamespace class to wrap the mapping's namespace
            return Class.new(Lutaml::Model::XmlNamespace) do
              uri xml_mapping.namespace_uri
              prefix_default xml_mapping.namespace_prefix
            end
          end
        end

        nil
      end

      # Get namespace URI from type
      #
      # @param register [Symbol, nil] register ID for type resolution
      # @return [String, nil] namespace URI
      def type_namespace_uri(register = nil)
        type_namespace_class(register)&.uri
      end

      # Get namespace prefix from type
      #
      # @param register [Symbol, nil] register ID for type resolution
      # @return [String, nil] namespace prefix
      def type_namespace_prefix(register = nil)
        type_namespace_class(register)&.prefix_default
      end

      private

      def validate_attr_type!(resolved_type)
        return true if resolved_type <= Serializable || resolved_type <= Type::Value
        return true if resolved_type.included_modules.include?(Serialize)

        raise Lutaml::Model::InvalidAttributeTypeError.new(name, resolved_type.name)
      end

      def validated_range_object
        return collection if collection.end

        collection.begin..Float::INFINITY
      end

      def validate_name!(name, reserved_methods:)
        return unless reserved_methods.include?(name.to_sym)

        if ALLOW_OVERRIDING.include?(name.to_sym)
          warn_name_conflict(name)
        else
          raise Lutaml::Model::InvalidAttributeNameError.new(name)
        end
      end

      def warn_name_conflict(name)
        Logger.warn(
          "Attribute name `#{name}` conflicts with a built-in method", caller_locations(5..5).first
        )
      end

      def resolve_polymorphic_class(type, value, options)
        return type unless polymorphic_map_defined?(options, value)

        val = value[options[:polymorphic][:attribute]]
        klass_name = options[:polymorphic][:class_map][val]
        Object.const_get(klass_name)
      end

      def polymorphic_map_defined?(polymorphic_options, value)
        !value.nil? &&
          polymorphic_options[:polymorphic] &&
          !polymorphic_options[:polymorphic].empty? &&
          value[polymorphic_options[:polymorphic][:attribute]]
      end

      def castable?(value, format)
        value.is_a?(::Hash) ||
          (format == :xml && value.is_a?(Lutaml::Model::Xml::XmlElement))
      end

      def can_serialize?(klass, value, format, options)
        return false unless klass <= Serialize

        castable?(value, format) || options[:converted]
      end

      def custom_collection?
        return false if singular?
        return false if collection == true
        return false if collection.is_a?(Range)

        collection <= Lutaml::Model::Collection
      end

      def needs_conversion?(klass, value)
        !value.nil? && !value.is_a?(klass) && Utils.initialized?(value)
      end

      def already_serialized?(klass, value)
        klass <= Serialize && value.is_a?(klass.model)
      end

      def serialize_array(value, format, register, options)
        value.map { |v| serialize(v, format, register, options) }
      end

      def serialize_model(value, format, register, options)
        as_options = options.merge(register: register)
        # Remove mappings from options for nested model serialization
        # Nested models should use their own format mappings
        as_options.delete(:mappings)
        return unless Utils.present?(value)

        resolved_type = as_options.delete(:resolved_type) || type(register)
        if value.is_a?(resolved_type)
          return value.class.as(format, value,
                                as_options)
        end

        resolved_type.as(format, value, as_options)
      end

      def serialize_value(value, format, resolved_type)
        value = wrap_in_type_if_needed(value, resolved_type)
        value.send(:"to_#{format}")
      end

      def wrap_in_type_if_needed(value, resolved_type)
        return value if value.is_a?(Type::Value)

        if resolved_type == Type::Reference
          create_reference_instance(resolved_type, value)
        else
          resolved_type.new(value)
        end
      end

      def create_reference_instance(resolved_type, key = nil)
        resolved_type.new(@options[:ref_model_class],
                          @options[:ref_key_attribute], key)
      end

      def validate_presence!(type)
        return if type

        raise ArgumentError, "type must be set for an attribute"
      end

      def validate_required!(value)
        return if required_value_set?(value)

        raise Lutaml::Model::RequiredAttributeMissingError.new(name)
      end

      def set_default_for_collection
        validate_collection_range
        attr = self
        @options[:default] ||= -> { attr.build_collection } if initialize_empty?
      end

      def validate_options!(options)
        if (invalid_opts = options.keys - ALLOWED_OPTIONS).any?
          raise Lutaml::Model::InvalidAttributeOptionsError.new(name,
                                                                invalid_opts)
        end

        # Deprecation warning for :xsd_type attribute option
        if options.key?(:xsd_type)
          warn "[DEPRECATION] The :xsd_type attribute option is deprecated and will be removed in v1.0.0. " \
               "Create a custom Type::Value class with xsd_type at class level instead. " \
               "See: docs/migration-guides/xsd-type-migration.adoc " \
               "Called from #{caller(1..1).first}"
        end

        # No need to change user register#get_class, only checks if type is LutaML-Model string.
        # Using MODEL_STRINGS since pattern is only supported for String type.
        if options.key?(:pattern) && !MODEL_STRINGS.include?(type)
          raise StandardError,
                "Invalid option `pattern` given for `#{name}`, " \
                "`pattern` is only allowed for :string type"
        end

        if initialize_empty? && !collection?
          raise StandardError,
                "Invalid option `initialize_empty` given without `collection: true` option"
        end
        true
      end

      def validate_type!(type)
        return true if [Symbol,
                        String].include?(type.class) || type.is_a?(Class)

        raise ArgumentError,
              "Invalid type: #{type}, must be a Symbol, String or a Class"
      end

      def valid_polymorphic_type?(value, resolved_type)
        return value.is_a?(type) unless has_polymorphic_list?

        options[:polymorphic].include?(value.class) && value.is_a?(resolved_type)
      end

      def has_polymorphic_list?
        options[:polymorphic]&.is_a?(Array)
      end
    end
  end
end
