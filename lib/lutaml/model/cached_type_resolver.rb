# frozen_string_literal: true

module Lutaml
  module Model
    # CachedTypeResolver adds caching to any TypeResolver using the Decorator pattern.
    #
    # This is an INTERNAL class. Users should use Register and GlobalRegister.
    #
    # Responsibility: Add caching to type resolution
    #
    # This class:
    # - Decorates any TypeResolver-like object (duck typing)
    # - Uses a simple hash-based cache with context-aware keys
    # - Thread-safe with Mutex protection
    # - Centralized cache management - ONE place to clear ALL type caches
    #
    # @api private
    #
    # @example Basic usage
    #   resolver = CachedTypeResolver.new(delegate: TypeResolver)
    #   resolver.resolve(:string, context)  # First call - resolves and caches
    #   resolver.resolve(:string, context)  # Second call - returns cached
    #
    # @example Clearing caches
    #   resolver.clear_cache(:my_context)  # Clear cache for specific context
    #   resolver.clear_all_caches          # Clear all caches
    #
    class CachedTypeResolver
      # @return [Object] The delegate resolver (typically TypeResolver)
      attr_reader :delegate

      # Create a new CachedTypeResolver.
      #
      # @param delegate [Object] Any object responding to #resolve(name, context)
      def initialize(delegate:)
        @delegate = delegate
        @cache = {}
        @mutex = Mutex.new
      end

      # Resolve a type name to a class, using cache if available.
      #
      # @param name [Symbol, String, Class] The type name or class to resolve
      # @param context [TypeContext] The resolution context
      # @return [Class] The resolved type class
      # @raise [UnknownTypeError] If type cannot be resolved
      def resolve(name, context)
        # Always delegate to allow substitution even for class types
        # But only cache non-class results
        if name.is_a?(Class)
          @delegate.resolve(name, context)
        else
          cache_key = build_cache_key(name, context)

          @mutex.synchronize do
            @cache[cache_key] ||= @delegate.resolve(name, context)
          end
        end
      end

      # Check if a type can be resolved, using cache if available.
      #
      # @param name [Symbol, String, Class] The type name or class to check
      # @param context [TypeContext] The resolution context
      # @return [Boolean] true if type can be resolved
      def resolvable?(name, context)
        return true if name.is_a?(Class)

        cache_key = build_cache_key(name, context)

        @mutex.synchronize do
          @cache.key?(cache_key) || @delegate.resolvable?(name, context)
        end
      end

      # Try to resolve a type, returning nil if not found.
      #
      # @param name [Symbol, String, Class] The type name or class to resolve
      # @param context [TypeContext] The resolution context
      # @return [Class, nil] The resolved type class or nil
      def resolve_or_nil(name, context)
        resolve(name, context)
      rescue UnknownTypeError
        nil
      end

      # Clear the cache for a specific context.
      #
      # @param context_id [Symbol] The context ID to clear caches for
      # @return [void]
      def clear_cache(context_id)
        @mutex.synchronize do
          @cache.delete_if { |key, _| key.start_with?("#{context_id}:") }
        end
      end

      # Clear all caches.
      #
      # @return [void]
      def clear_all_caches
        @mutex.synchronize do
          @cache.clear
        end
      end

      # Get cache statistics (useful for debugging/monitoring).
      #
      # @return [Hash] Cache statistics
      def cache_stats
        @mutex.synchronize do
          {
            size: @cache.size,
            keys: @cache.keys,
          }
        end
      end

      private

      # Build a cache key from name and context.
      #
      # @param name [Symbol, String] The type name
      # @param context [TypeContext] The resolution context
      # @return [String] The cache key
      def build_cache_key(name, context)
        "#{context.id}:#{name}"
      end
    end
  end
end
