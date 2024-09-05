module Lutaml
  module Model
    class Attribute
      attr_reader :name, :type, :options

      def initialize(name, type, options = {})
        @name = name
        @type = cast_type(type)

        @options = options

        if collection? && !options[:default]
          @options[:default] = -> { [] }
        end
      end

      def cast_type(type)
        case type
        when Class
          type
        when String
          Type.const_get(type)
        when Symbol
          Type.const_get(type.to_s.split("_").collect(&:capitalize).join)
        end
      rescue NameError
        raise ArgumentError, "Unknown Lutaml::Model::Type: #{type}"
      end

      def collection?
        options[:collection] || false
      end

      def singular?
        !collection?
      end

      def default
        return options[:default].call if options[:default].is_a?(Proc)

        options[:default]
      end

      def render_nil?
        options.fetch(:render_nil, false)
      end

      def enum_values
        @options.key?(:values) ? @options[:values] : []
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
        # return true if none of the validations are present
        return true if enum_values.empty? && singular?

        # Use the default value if the value is nil
        value = default if value.nil?

        valid_value!(value) && valid_collection!(value)
      end

      def valid_value?(value)
        return true unless options[:values]

        options[:values].include?(value)
      end

      def valid_value!(value)
        unless valid_value?(value)
          raise Lutaml::Model::InvalidValueError.new(name, value, enum_values)
        end

        true
      end

      def valid_collection?(value)
        return true unless collection?
        return false unless value.is_a?(Array)
        return collection? if options[:collection].boolean?

        options[:collection].include?(value.count)
      end

      def valid_collection!(value)
        unless valid_collection?(value)
          raise(
            Lutaml::Model::CollectionCountOutOfRangeError.new(
              name,
              value,
              options[:collection],
            ),
          )
        end

        true
      end

      def serialize(value, format, options = {})
        if value.is_a?(Array)
          value.map do |v|
            serialize(v, format, options)
          end
        elsif type <= Serialize
          type.hash_representation(value, format, options)
        else
          type.serialize(value)
        end
      end

      def cast(value, format, options = {})
        value ||= [] if collection?
        instance = options[:instance]

        if value.is_a?(Array)
          value.map do |v|
            cast(v, format, instance: instance)
          end
        elsif type <= Serialize && value.is_a?(Hash)
          type.apply_mappings(value, format, options)
        else
          Lutaml::Model::Type.cast(value, type)
        end
      end
    end
  end
end
