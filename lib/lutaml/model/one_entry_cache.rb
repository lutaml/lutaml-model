# frozen_string_literal: true

module Lutaml
  module Model
    # A single-entry cache that stores one key-value pair at a time.
    # Used for MappingRule#namespaced_names where the same parent_namespace
    # is queried repeatedly for all rules of a given element.
    #
    # When the key changes, the old entry is replaced. This avoids
    # hash allocation for the common case of a single repeated key.
    class OneEntryCache
      def initialize
        @key = nil
        @value = nil
        @filled = false
      end

      # Returns the cached value if key matches, nil otherwise.
      # Uses @filled flag to distinguish "no cache" from "cached nil".
      def fetch(key)
        return nil unless @filled
        return @value if @key == key

        nil
      end

      # Store a value for the given key, replacing any previous entry.
      def store(key, value)
        @key = key
        @value = value
        @filled = true
        value
      end

      # Fetch cached value, computing via block on cache miss.
      def fetch_or_compute(key)
        cached = fetch(key)
        return cached unless cached.nil?

        value = yield
        store(key, value)
        value
      end

      # Clear the cached entry.
      def clear
        @key = nil
        @value = nil
        @filled = false
      end

      def empty?
        !@filled
      end
    end
  end
end
