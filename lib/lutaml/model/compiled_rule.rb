# frozen_string_literal: true

module Lutaml
  module Model
    # Pre-compiled transformation rule for efficient serialization.
    #
    # A CompiledRule contains all information needed to transform a model
    # attribute into its serialized representation without triggering
    # type resolution or imports during transformation.
    #
    # CompiledRules are frozen after creation to ensure immutability.
    class CompiledRule
      # @return [Symbol] The attribute name in the model
      attr_reader :attribute_name

      # @return [String] The serialized name (element/key name)
      attr_reader :serialized_name

      # @return [Symbol, Class, nil] The attribute type
      attr_reader :attribute_type

      # @return [Transformation, nil] Pre-compiled transformation for nested models
      attr_reader :child_transformation

      # @return [Proc, nil] Value transformation lambda
      attr_reader :value_transformer

      # @return [Hash, nil] Collection metadata (range, etc.)
      attr_reader :collection_info

      # @return [Class, nil] Namespace class for XML
      attr_reader :namespace_class

      # @return [Hash] Additional rule-specific options
      attr_reader :options

      # @return [Hash] Custom serialization methods ({to: ..., from: ...})
      attr_reader :custom_methods

      # Initialize a new compiled rule
      #
      # @param attribute_name [Symbol] The attribute name in the model
      # @param serialized_name [String] The serialized name
      # @param attribute_type [Symbol, Class, nil] The attribute type
      # @param child_transformation [Transformation, nil] Pre-compiled child transformation
      # @param value_transformer [Proc, nil] Value transformation lambda
      # @param collection_info [Hash, nil] Collection metadata
      # @param namespace_class [Class, nil] Namespace class for XML
      # @param custom_methods [Hash] Custom serialization methods ({to: ..., from: ...})
      # @param options [Hash] Additional options
      def initialize(
        attribute_name:,
        serialized_name:,
        attribute_type: nil,
        child_transformation: nil,
        value_transformer: nil,
        collection_info: nil,
        namespace_class: nil,
        custom_methods: nil,
        **options
      )
        @attribute_name = attribute_name
        @serialized_name = serialized_name
        @attribute_type = attribute_type
        @child_transformation = child_transformation
        @value_transformer = value_transformer
        @collection_info = collection_info
        @namespace_class = namespace_class
        @custom_methods = custom_methods || {}
        @options = options
        freeze
      end

      # Check if this rule represents a collection
      #
      # @return [Boolean] true if attribute is a collection
      def collection?
        !collection_info.nil?
      end

      # Check if this rule represents a nested model
      #
      # @return [Boolean] true if attribute is a nested model
      def nested_model?
        !child_transformation.nil?
      end

      # Check if this rule has custom serialization methods
      #
      # @return [Boolean] true if has custom methods
      def has_custom_methods?
        !custom_methods.empty?
      end

      # Collect all namespaces used in this rule and its children
      #
      # This method recursively traverses child transformations to collect
      # all namespace classes without triggering type resolution.
      #
      # @return [Array<Class>] Array of XmlNamespace classes
      def all_namespaces
        namespaces = []

        # Add this rule's namespace if present
        namespaces << namespace_class if namespace_class

        # Recursively collect from child transformation
        if child_transformation
          namespaces.concat(child_transformation.all_namespaces)
        end

        namespaces.uniq
      end

      # Get collection range if this is a collection
      #
      # @return [Range, nil] Collection range or nil
      def collection_range
        collection_info&.fetch(:range, nil)
      end

      # Check if collection allows multiple values
      #
      # @return [Boolean] true if collection allows more than one value
      def multiple_values?
        return false unless collection?

        range = collection_range
        return true if range.nil? # unbounded collection

        range.end.nil? || range.end > 1
      end

      # Apply value transformation if present
      #
      # @param value [Object] The value to transform
      # @param direction [Symbol] :export or :import
      # @return [Object] Transformed value
      def transform_value(value, direction = :export)
        return value unless value_transformer

        if value_transformer.is_a?(::Hash)
          transformer = value_transformer[direction]
          transformer ? transformer.call(value) : value
        elsif value_transformer.is_a?(Proc)
          value_transformer.call(value)
        else
          value
        end
      end

      # Get an option value
      #
      # @param key [Symbol] The option key
      # @param default [Object] Default value if not found
      # @return [Object] The option value or default
      def option(key, default = nil)
        options.fetch(key, default)
      end

      # Handle method calls for accessing options dynamically
      #
      # This allows options to be accessed as methods (e.g., rule.cdata, rule.raw, rule.mixed_content)
      # instead of using rule.option(:cdata)
      #
      # @param method_name [Symbol] The method name to look up
      # @param args [Array] Arguments (ignored for options)
      # @param block [Proc] Block (ignored for options)
      # @return [Object] The option value or nil
      def method_missing(method_name, *args, &block)
        # Check if this is an option key
        if options.key?(method_name)
          return options[method_name]
        end

        # Fall back to default method_missing behavior
        super
      end

      # Check if an option or method exists
      #
      # @param method_name [Symbol] The method name to check
      # @param include_private [Boolean] Whether to include private methods
      # @return [Boolean] true if the method exists
      def respond_to_missing?(method_name, include_private = false)
        options.key?(method_name) || super
      end
    end
  end
end