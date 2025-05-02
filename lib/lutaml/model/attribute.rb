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
        method_name
        polymorphic
        polymorphic_class
        initialize_empty
      ].freeze

      def initialize(name, type, options = {})
        @name = name
        @options = options

        validate_presence!(type, options[:method_name])
        @type = type
        process_options!
      end

      def type(register = Lutaml::Model::Config.default_register)
        register.get_class(unresolved_type) unless unresolved_type.nil?
      end

      def unresolved_type
        @type
      end

      def polymorphic?
        @options[:polymorphic_class]
      end

      def derived?
        unresolved_type.nil?
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

      def cast_value(value, register)
        return type(register).cast(value) unless value.is_a?(Array)

        value.map { |v| type(register).cast(v) }
      end

      def setter
        :"#{@name}="
      end

      def collection?
        options[:collection] || false
      end

      def singular?
        !collection?
      end

      def raw?
        @raw
      end

      def enum?
        !enum_values.empty?
      end

      def default(register = Lutaml::Model::Config.default_register)
        cast_value(default_value(register), register)
      end

      def default_value(register)
        if delegate
          type(register).attributes[to].default(register)
        elsif options[:default].is_a?(Proc)
          options[:default].call
        elsif options.key?(:default)
          options[:default]
        else
          Lutaml::Model::UninitializedClass.instance
        end
      end

      def default_set?(register)
        !Utils.uninitialized?(default_value(register))
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

      def valid_pattern!(value, register)
        return true unless type(register) == Lutaml::Model::Type::String
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
      def validate_value!(value, register)
        # Use the default value if the value is nil
        value = default(register) if value.nil?

        valid_value!(value) &&
          valid_collection!(value, self) &&
          valid_pattern!(value, register) &&
          validate_polymorphic!(value, register)
      end

      def validate_polymorphic(value, register)
        return value.all? { |v| validate_polymorphic!(v, register) } if value.is_a?(Array)
        return true unless options[:polymorphic]

        valid_polymorphic_type?(value, register)
      end

      def validate_polymorphic!(value, register)
        return true if validate_polymorphic(value, register)

        raise Lutaml::Model::PolymorphicError.new(value, options, type(register))
      end

      def validate_collection_range
        range = @options[:collection]
        return if range == true

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
        raise Lutaml::Model::CollectionTrueMissingError.new(name, caller) if value.is_a?(Array) && !collection?

        return true unless collection?

        # Allow any value for unbounded collections
        return true if options[:collection] == true

        unless value.is_a?(Array)
          raise Lutaml::Model::CollectionCountOutOfRangeError.new(
            name,
            value,
            options[:collection],
          )
        end

        range = options[:collection]
        return true unless range.is_a?(Range)

        if range.end.nil?
          if value.size < range.begin
            raise Lutaml::Model::CollectionCountOutOfRangeError.new(
              name,
              value,
              range,
            )
          end
        elsif !range.cover?(value.size)
          raise Lutaml::Model::CollectionCountOutOfRangeError.new(
            name,
            value,
            range,
          )
        end
      end

      def serialize(value, format, register, options = {})
        value ||= [] if collection? && initialize_empty?
        return value if value.nil? || Utils.uninitialized?(value)
        return value if derived?
        return serialize_array(value, format, register, options) if value.is_a?(Array)
        return serialize_model(value, format, register, options) if type(register) <= Serialize

        serialize_value(value, format, register)
      end

      def cast(value, format, register, options = {})
        value ||= [] if collection? && !value.nil?
        registered_type = type(register)
        return value.map { |v| cast(v, format, register, options) } if value.is_a?(Array)
        return value if already_serialized?(registered_type, value)

        klass = resolve_polymorphic_class(registered_type, value, options)
        if can_serialize?(klass, value, format)
          klass.apply_mappings(value, format, options.merge(register: register))
        elsif needs_conversion?(klass, value)
          klass.send(:"from_#{format}", value)
        else
          # No need to use register#get_class,
          # can_serialize? method already checks if type is Serializable or not.
          Type.lookup(klass).cast(value)
        end
      end

      def deep_dup
        self.class.new(name, unresolved_type, Utils.deep_dup(options))
      end

      private

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
        value.is_a?(Hash) ||
          (format == :xml && value.is_a?(Lutaml::Model::Xml::XmlElement))
      end

      def can_serialize?(klass, value, format)
        klass <= Serialize && castable?(value, format)
      end

      def needs_conversion?(klass, value)
        !value.nil? && !value.is_a?(klass)
      end

      def already_serialized?(klass, value)
        klass <= Serialize && value.is_a?(klass.model)
      end

      def serialize_array(value, format, register, options)
        value.map { |v| serialize(v, format, register, options) }
      end

      def serialize_model(value, format, register, options)
        as_options = options.merge(register: register)
        return unless Utils.present?(value)
        return value.class.as(format, value, as_options) if value.is_a?(type(register))

        type(register).as(format, value, as_options)
      end

      def serialize_value(value, format, register)
        value = type(register).new(value) unless value.is_a?(Type::Value)
        value.send(:"to_#{format}")
      end

      def validate_presence!(type, method_name)
        return if type || method_name

        raise ArgumentError, "method or type must be set for an attribute"
      end

      def process_options!
        validate_options!(@options)
        @raw = !!@options[:raw]
        set_default_for_collection if collection?
      end

      def set_default_for_collection
        validate_collection_range
        @options[:default] ||= -> { [] } if initialize_empty?
      end

      def validate_options!(options)
        if (invalid_opts = options.keys - ALLOWED_OPTIONS).any?
          raise StandardError,
                "Invalid options given for `#{name}` #{invalid_opts}"
        end

        # No need to change user register#get_class, only checks if type is LutaML-Model string.
        if options.key?(:pattern) && Type.lookup(type) != Lutaml::Model::Type::String
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
        return true if [Symbol, String].include?(type.class) || type.is_a?(Class)

        raise ArgumentError,
              "Invalid type: #{type}, must be a Symbol, String or a Class"
      end

      def valid_polymorphic_type?(value, register)
        return value.is_a?(type) unless has_polymorphic_list?

        options[:polymorphic].include?(value.class) && value.is_a?(type(register))
      end

      def has_polymorphic_list?
        options[:polymorphic]&.is_a?(Array)
      end
    end
  end
end
