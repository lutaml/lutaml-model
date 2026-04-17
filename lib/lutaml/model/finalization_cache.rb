# frozen_string_literal: true

module Lutaml
  module Model
    # A hash-backed cache that only stores values after finalization.
    # Used by Xml::Mapping for caching elements/attributes/mappings
    # after the mapping definition is complete.
    #
    # Before finalization, fetch_or_store computes but does not cache.
    # After finalization, results are cached and frozen per key.
    # Calling finalize! clears all cached entries.
    class FinalizationCache
      def initialize
        @store = {}
        @finalized = false
      end

      def finalized?
        @finalized
      end

      # Mark the cache as finalized and clear any stale entries.
      # Called when the mapping definition is complete.
      def finalize!
        @store.clear
        @finalized = true
      end

      # Fetch a cached value by key. Returns nil if not found.
      def fetch(key)
        @store[key]
      end

      # Fetch cached value, computing via block on cache miss.
      # Only caches and freezes the result after finalization.
      def fetch_or_store(key)
        cached = @store[key]
        return cached if cached

        value = yield
        @store[key] = value.freeze if @finalized
        value
      end

      # Clear cached entries without changing finalized status.
      def clear
        @store.clear
      end
    end
  end
end
