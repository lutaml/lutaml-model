# frozen_string_literal: true

module Lutaml
  module Model
    # Module for handling collection-related operations on attributes.
    #
    # Provides methods for checking if an attribute is a collection,
    # getting the collection class, building collections, and related operations.
    module CollectionHandler
      # Get the collection options
      #
      # @return [Object, nil] The collection option value
      def collection
        @options[:collection]
      end

      # Check if this attribute is a collection
      # Performance: Memoized to avoid repeated hash lookups
      #
      # @return [Boolean] true if attribute is a collection
      def collection?
        @collection ||= collection || false
      end

      # Check if this attribute is a singular (non-collection) value
      # Performance: Memoized
      #
      # @return [Boolean] true if attribute is not a collection
      def singular?
        @singular ||= !collection?
      end

      # Get the collection class to use for this attribute
      # Performance: Memoized
      #
      # @return [Class] The collection class (Array or custom collection class)
      def collection_class
        @collection_class ||= custom_collection? ? collection : Array
      end

      # Check if value is an instance of the collection class
      #
      # @param value [Object] The value to check
      # @return [Boolean] true if value is a collection instance
      def collection_instance?(value)
        value.is_a?(collection_class)
      end

      # Build a new collection with the given values
      #
      # Custom Collection classes resolve their item type through the register,
      # so thread it through when one is supplied. Plain Array collections and
      # register-less callers keep the prior construction path untouched.
      #
      # @param args [Array] Values to include in the collection
      # @param register [Symbol, nil] Register for custom-collection type resolution
      # @return [Object] A new collection instance
      def build_collection(*args, register: nil)
        items = args.flatten
        return collection_class.new(items) unless custom_collection? && register

        collection_class.new(items, lutaml_register: register)
      end

      # Whether a bare single value assigned to this attribute must be
      # coerced into a one-element collection, so assignment produces the
      # same shape as parsing. nil and the uninitialized sentinel pass
      # through untouched to preserve absent-value semantics.
      #
      # @param value [Object] The value being assigned
      # @return [Boolean] true if the value should be wrapped
      def coerce_to_collection?(value)
        collection? && !value.nil? && !Utils.uninitialized?(value)
      end

      # Check if this attribute uses a custom collection class
      # Performance: Memoized
      #
      # @return [Boolean] true if using a custom collection class
      def custom_collection?
        return @custom_collection if defined?(@custom_collection)

        @custom_collection = if singular?
                               false
                             elsif collection == true
                               false
                             elsif collection.is_a?(Range)
                               false
                             else
                               collection <= Lutaml::Model::Collection
                             end
      end

      # Get the resolved collection range
      # Performance: Memoized
      #
      # @return [Range, nil] The collection range or nil if not a collection
      def resolved_collection
        @resolved_collection ||= begin
          return unless collection?

          collection.is_a?(Range) ? validated_range_object : 0..Float::INFINITY
        end
      end

      # Check if the collection minimum is zero
      #
      # @return [Boolean] true if collection min is zero
      def min_collection_zero?
        collection? && resolved_collection.min.zero?
      end

      private

      # Get validated range object for collection
      #
      # @return [Range] The validated range
      def validated_range_object
        return collection if collection.end

        collection.begin..Float::INFINITY
      end
    end
  end
end
