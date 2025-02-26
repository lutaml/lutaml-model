module Lutaml
  module Model
    class Attribute
      attr_reader :name, :type, :options

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
      ].freeze

      def initialize(name, type, options = {})
        @name = name
        @options = options

        validate_presence!(type, options[:method_name])
        process_type!(type) if type
        process_options!
      end

      def polymorphic?
        @options[:polymorphic_class]
      end

      def derived?
        type.nil?
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

      def cast_type!(type)
        case type
        when Symbol
          begin
            Type.lookup(type)
          rescue UnknownTypeError
            raise ArgumentError, "Unknown Lutaml::Model::Type: #{type}"
          end
        when String
          begin
            Type.const_get(type)
          rescue NameError
            raise ArgumentError, "Unknown Lutaml::Model::Type: #{type}"
          end
        when Class
          type
        else
          raise ArgumentError, "Unknown Lutaml::Model::Type: #{type}"
        end
      end

      def cast_value(value)
        return type.cast(value) unless value.is_a?(Array)

        value.map { |v| type.cast(v) }
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

      def default
        cast_value(default_value)
      end

      def default_value
        if delegate
          type.attributes[to].default
        elsif options[:default].is_a?(Proc)
          options[:default].call
        else
          options[:default]
        end
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

        unless valid_value?(value)
          raise Lutaml::Model::InvalidValueError.new(name, value, enum_values)
        end

        true
      end

      def valid_value?(value)
        return true unless options[:values]

        options[:values].include?(value)
      end

      def valid_pattern!(value)
        return true unless type == Lutaml::Model::Type::String
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
      def validate_value!(value)
        # Use the default value if the value is nil
        value = default if value.nil?

        valid_value!(value) &&
          valid_collection!(value, self) &&
          valid_pattern!(value) &&
          validate_polymorphic!(value)
      end

      def validate_polymorphic(value)
        return value.all? { |v| validate_polymorphic!(v) } if value.is_a?(Array)
        return true unless polymorphic_enabled?

        valid_polymorphic_type?(value)
      end

      def validate_polymorphic!(value)
        return true if validate_polymorphic(value)

        raise StandardError, "#{value.class} not in #{options[:polymorphic]}"
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

        # Allow nil values for collections during initialization
        return true if value.nil?

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

      def serialize(value, format, options = {})
        return if value.nil?
        return value if derived?
        return serialize_array(value, format, options) if value.is_a?(Array)
        return serialize_model(value, format, options) if type <= Serialize

        serialize_value(value, format)
      end

      def cast(value, format, options = {})
        value ||= [] if collection?
        return value.map { |v| cast(v, format, options) } if value.is_a?(Array)

        return value if already_serialized?(type, value)

        klass = resolve_polymorphic_class(type, value, options)

        if can_serialize?(klass, value, format)
          klass.apply_mappings(value, format, options)
        elsif needs_conversion?(klass, value)
          klass.send(:"from_#{format}", value)
        else
          klass.cast(value)
        end
      end

      private

      def resolve_polymorphic_class(type, value, options)
        return type unless polymorphic_map_defined?(options, value)

        val = value[options[:polymorphic][:attribute]]
        klass_name = options[:polymorphic][:class_map][val]
        Object.const_get(klass_name)
      end

      def polymorphic_map_defined?(options, value)
        !value.nil? &&
          options[:polymorphic] &&
          !options[:polymorphic].empty? &&
          value[options[:polymorphic][:attribute]]
      end

      def castable?(value, format)
        value.is_a?(Hash) ||
          (format == :xml && value.is_a?(Lutaml::Model::XmlAdapter::XmlElement))
      end

      def castable_serialized_type?(value)
        type <= Serialize && value.is_a?(type.model)
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

      def serialize_array(value, format, options)
        value.map { |v| serialize(v, format, options) }
      end

      def serialize_model(value, format, options)
        return unless Utils.present?(value)
        return value.class.as(format, value, options) if value.is_a?(type)

        type.as(format, value, options)
      end

      def serialize_value(value, format)
        value = type.new(value) unless value.is_a?(Type::Value)
        value.send(:"to_#{format}")
      end

      def validate_presence!(type, method_name)
        return if type || method_name

        raise ArgumentError, "method or type must be set for an attribute"
      end

      def process_type!(type)
        validate_type!(type)
        @type = cast_type!(type)
      end

      def process_options!
        validate_options!(@options)
        @raw = !!@options[:raw]
        set_default_for_collection if collection?
      end

      def set_default_for_collection
        validate_collection_range
        @options[:default] ||= -> { [] }
      end

      def validate_options!(options)
        if (invalid_opts = options.keys - ALLOWED_OPTIONS).any?
          raise StandardError,
                "Invalid options given for `#{name}` #{invalid_opts}"
        end

        if options.key?(:pattern) && type != Lutaml::Model::Type::String
          raise StandardError,
                "Invalid option `pattern` given for `#{name}`, " \
                "`pattern` is only allowed for :string type"
        end

        true
      end

      def validate_type!(type)
        return true if type.is_a?(Class)
        return true if [Symbol, String].include?(type.class) && cast_type!(type)

        raise ArgumentError,
              "Invalid type: #{type}, must be a Symbol, String or a Class"
      end

      def polymorphic_enabled?
        options[:polymorphic]&.any?
      end

      def valid_polymorphic_type?(value)
        value.is_a?(type) && options[:polymorphic].include?(value.class)
      end
    end
  end
end
