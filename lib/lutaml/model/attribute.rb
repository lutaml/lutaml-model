# frozen_string_literal: true

module Lutaml
  module Model
    class Attribute
      attr_reader :name, :options

      include CollectionHandler

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

      # Methods where accidental override is likely to cause issues
      # All names are allowed - this list only controls which ones get a warning
      WARN_ON_OVERRIDE = %i[
        # Ruby core - overriding breaks fundamental behavior
        hash object_id class send method

        # Object lifecycle - overriding without super breaks things
        initialize

        # Serialization methods - overriding breaks serialization
        to_xml to_json to_yaml to_toml to_hash to_format

        # Internal helpers - overriding breaks internal logic
        attr_value attribute_exist? key_exist? key_value
        using_default? using_default_for value_set_for
        method_missing respond_to_missing?

        # XML metadata - affects XML processing
        element_order schema_location encoding doctype ordered? mixed?
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
        skip_validation = options.fetch(:skip_validation, false)

        unless skip_validation
          validate_name!(
            name, reserved_methods: Lutaml::Model::Serializable.instance_methods
          )
        end

        @name = name
        @options = options.except(:skip_validation)

        validate_presence!(type) unless skip_validation
        @type = type
        process_options! unless skip_validation
      end

      def type(context_or_register = nil)
        return if unresolved_type.nil?

        # Performance: Fast path for default context (most common case)
        # Cache the result to avoid mutex overhead in CachedTypeResolver
        if context_or_register.nil?
          return @cached_type_default ||= begin
            context = normalize_context(nil)
            GlobalContext.resolver.resolve(unresolved_type, context)
          end
        end

        # Check if we have a Register available for backward compatibility
        # If so, use Register's resolution which includes type substitutions
        fallback_register = extract_register(context_or_register)

        if fallback_register
          # Use Register for resolution (includes substitutions)
          begin
            return fallback_register.get_class_without_register(unresolved_type)
          rescue Lutaml::Model::UnknownTypeError
            # Fall through to GlobalContext
          end
        end

        # Use GlobalContext.resolver for centralized caching
        context = normalize_context(context_or_register)
        GlobalContext.resolver.resolve(unresolved_type, context)
      end

      # @api public
      # Get type with namespace-aware resolution.
      #
      # Uses the register's resolve_in_namespace method for version-aware
      # type resolution. Falls back to standard resolution if no namespace
      # or register is provided.
      #
      # @param register [Lutaml::Model::Register, Symbol, nil] The register or register ID
      # @param namespace_uri [String, nil] The namespace URI for version awareness
      # @return [Class, nil] The type class or nil
      def type_with_namespace(register, namespace_uri = nil)
        return type(register) unless register && namespace_uri
        return if unresolved_type.nil?

        # Resolve register from symbol if needed
        actual_register = if register.is_a?(Symbol)
                            Lutaml::Model::GlobalRegister.lookup(register)
                          else
                            register
                          end

        # If we don't have an actual Register object, fall back to standard resolution
        return type(register) unless actual_register.respond_to?(:resolve_in_namespace)

        # Try namespace-aware resolution first
        result = actual_register.resolve_in_namespace(unresolved_type,
                                                      namespace_uri)
        return result if result

        # Fallback to standard resolution
        type(register)
      end

      # Extract the Register from the context_or_register argument
      def extract_register(_context_or_register)
        # Register backward compatibility - now always returns nil
        # Type resolution uses GlobalContext directly
        nil
      end

      # Normalize register/context to TypeContext for resolution
      # Performance: Optimized to reduce allocations in hot path
      def normalize_context(context_or_register)
        # Fast path for nil - most common case
        return default_type_context if context_or_register.nil?

        # Fast path for TypeContext - no conversion needed
        return context_or_register if context_or_register.is_a?(Lutaml::Model::TypeContext)

        # Handle Register and Symbol cases
        context_id = case context_or_register
                     when Lutaml::Model::Register
                       context_or_register.id
                     when Symbol
                       context_or_register
                     else
                       return GlobalContext.default_context
                     end

        GlobalContext.context(context_id) || GlobalContext.default_context
      end

      # Performance: Cache default type context lookup
      def default_type_context
        @default_type_context ||= begin
          default_id = Lutaml::Model::Config.default_register
          ctx = GlobalContext.context(default_id)
          ctx || GlobalContext.default_context
        end
      end

      def unresolved_type
        @unresolved_type ||= @type
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

      # Performance: Frozen empty hash to reduce allocations
      EMPTY_TRANSFORM_HASH = {}.freeze

      def transform
        @options[:transform] || EMPTY_TRANSFORM_HASH
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

      # Collection methods are provided by CollectionHandler module

      def raw?
        @raw
      end

      def enum?
        !enum_values.empty?
      end

      def default(register = Lutaml::Model::Config.default_register,
instance_object = nil)
        cast_value(default_value(register, instance_object), register)
      end

      def default_value(register, instance_object = nil)
        if delegate
          type(register).attributes(register)[to].default(register,
                                                          instance_object)
        elsif options[:default].is_a?(Proc)
          if instance_object
            instance_object.instance_exec(&options[:default])
          else
            options[:default].call
          end
        elsif options.key?(:default)
          options[:default]
        else
          Lutaml::Model::UninitializedClass.instance
        end
      end

      def default_set?(register, instance_object = nil)
        !Utils.uninitialized?(default_value(register, instance_object))
      end

      def pattern
        options[:pattern]
      end

      # Performance: Frozen empty array to reduce allocations
      EMPTY_VALUES_ARRAY = [].freeze

      def enum_values
        @options.key?(:values) ? @options[:values] : EMPTY_VALUES_ARRAY
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
        # Namespace-aware type resolution: use type_with_namespace if namespace_uri provided
        namespace_uri = options[:namespace_uri]
        resolved_type = if options[:resolved_type]
                          options[:resolved_type]
                        elsif register && namespace_uri
                          type_with_namespace(register, namespace_uri)
                        else
                          type(register)
                        end
        if collection_instance?(value) || value.is_a?(Array)
          return build_collection(value.map do |v|
            cast(v, format, register,
                 options.merge(resolved_type: resolved_type, converted: true))
          end)
        end

        return value if already_serialized?(resolved_type, value)

        # Special handling for Reference types - pass the metadata
        # Check @options[:ref_model_class] which is set when type is { ref: [...] }
        if @options[:ref_model_class] && resolved_type == Lutaml::Model::Type::Reference
          return resolved_type.cast_with_metadata(value,
                                                  @options[:ref_model_class], @options[:ref_key_attribute])
        end

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

      # resolved_collection is provided by CollectionHandler module

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

      # min_collection_zero? is provided by CollectionHandler module

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
        # Don't deep_dup the entire options hash because:
        # 1. Lambdas/Procs (like :default) should not be duplicated
        # 2. Classes (like :collection class) are immutable
        # 3. Deep dupping creates circular references when lambdas close over the attribute

        # Selectively copy options using direct type checks to avoid method calls
        duped_options = { skip_validation: true }
        options.each do |key, value|
          duped_options[key] = case value
                               when Symbol, TrueClass, FalseClass, Numeric, Class, Module, Proc, Method, NilClass
                                 value # Immutable, don't dup
                               when Range
                                 # Only dup if bounds are mutable strings
                                 if value.begin.is_a?(String) || (value.end && value.end.is_a?(String))
                                   Range.new(value.begin.dup, value.end&.dup, value.exclude_end?)
                                 else
                                   value # Immutable bounds, safe to reuse
                                 end
                               when Hash
                                 Utils.deep_dup(value)
                               when Array
                                 Utils.deep_dup(value)
                               else
                                 value # Keep as-is (might be a complex object)
                               end
        end

        # Skip validation during deep_dup - options are already validated in original
        # This prevents infinite recursion when process_options! tries to access collection
        self.class.new(name, unresolved_type, duped_options).tap do |dup_attr|
          # Copy already-processed instance variables directly
          dup_attr.instance_variable_set(:@raw, @raw)
          dup_attr.instance_variable_set(:@validations, @validations)
        end
      end

      # @api public
      # Get namespace class from Type::Value or Model class
      #
      # @param register [Symbol, nil] register ID for type resolution
      # @return [Class, nil] XmlNamespace class if type has namespace
      def type_namespace_class(register = nil)
        # NOTE: @type_namespace_cache removed - type() now uses GlobalContext.resolver
        # which handles caching centrally. No need for scattered caching here.

        # Resolve type namespace via type() which uses GlobalContext.resolver
        resolved_type = type(register)
        return nil if resolved_type.nil?

        # Check if type is a Type::Value class
        # Type namespaces are ONLY declared on Type::Value subclasses,
        # not on Serializable models. Serializable models have element
        # namespaces, which are handled separately.
        resolved_type.is_a?(Class) && resolved_type <= Lutaml::Model::Type::Value ? resolved_type.namespace_class : nil
      end

      # @api public
      # Get namespace URI from type
      #
      # @param register [Symbol, nil] register ID for type resolution
      # @return [String, nil] namespace URI
      def type_namespace_uri(register = nil)
        type_namespace_class(register)&.uri
      end

      # @api public
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
        return true if resolved_type.include?(Serialize)

        raise Lutaml::Model::InvalidAttributeTypeError.new(name,
                                                           resolved_type.name)
      end

      # validated_range_object is provided by CollectionHandler module

      def validate_name!(name, reserved_methods:)
        # No errors - all names are allowed
        # Only warn for methods where accidental override is problematic
        return unless reserved_methods.include?(name.to_sym)
        return unless WARN_ON_OVERRIDE.include?(name.to_sym)

        warn_name_conflict(name)
      end

      def warn_name_conflict(name)
        # Find the first caller location outside the lutaml-model gem's lib directory
        # This ensures we report the user's code line, not internal gem code
        gem_lib_pattern = %r{/lutaml-model.*/lib/}
        location = caller_locations.find do |cl|
          !gem_lib_pattern.match?(cl.path)
        end

        Logger.warn(
          "Attribute `#{name}` overrides a method. " \
          "Ensure you call `super` if needed, or consider renaming.",
          location || caller_locations(1..1).first,
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
          (format == :xml && value.is_a?(Lutaml::Xml::XmlElement))
      end

      def can_serialize?(klass, value, format, options)
        return false unless klass <= Serialize

        castable?(value, format) || options[:converted]
      end

      # custom_collection? is provided by CollectionHandler module

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
        # Use the value's own lutaml_register if available (proper OOP - model carries its context)
        # This ensures child models serialize using their native context, not the parent's
        value_register = if value.is_a?(Lutaml::Model::Serializable) && value.lutaml_register
                           value.lutaml_register
                         else
                           register
                         end

        as_options = options.merge(register: value_register)
        # Remove mappings from options for nested model serialization
        # Nested models should use their own format mappings
        as_options.delete(:mappings)

        # Respect mapping layer policy: render_empty from MappingRule
        # Allow empty Serializable models when render_empty: true
        render_empty = options[:render_empty]
        if render_empty && value.is_a?(Lutaml::Model::Serializable)
          # Mapping layer says render this empty model - bypass present check
        else
          return unless Utils.present?(value)
        end

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
