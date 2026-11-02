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
    # - Uses a runtime-selected cache backend
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
      RuntimeCompatibility.autoload_native(
        self,
        ConcurrentMapCache: "#{__dir__}/cached_type_resolver/concurrent_map_cache",
      )
      autoload :MutexHashCache,
               "#{__dir__}/cached_type_resolver/mutex_hash_cache"

      # @return [Object] The delegate resolver (typically TypeResolver)
      attr_reader :delegate, :cache_backend

      def self.default_cache_backend
        if Lutaml::Model.opal?
          MutexHashCache.new
        else
          ConcurrentMapCache.new
        end
      end

      # Create a new CachedTypeResolver.
      #
      # @param delegate [Object] Any object responding to #resolve(name, context)
      # @param cache_backend [Object] Any object implementing the resolver cache
      #   interface used internally by CachedTypeResolver
      def initialize(delegate:, cache_backend: self.class.default_cache_backend)
        @delegate = delegate
        @cache_backend = cache_backend
      end

      # Resolve a type name to a class, using cache if available.
      #
      # Cache backends synchronize storage, but compute outside exclusive cache
      # updates so recursive type resolution can populate related keys.
      #
      # @param name [Symbol, String, Class] The type name or class to resolve
      # @param context [TypeContext, nil] The resolution context
      # @return [Class] The resolved type class
      # @raise [UnknownTypeError] If type cannot be resolved
      def resolve(name, context, materialize: true)
        return @delegate.resolve(name, context, materialize: false) unless materialize

        @cache_backend.fetch_or_store(type_cache_key(name, context)) do
          @delegate.resolve(name, context)
        end
      end

      # Check if a type can be resolved, using cache if available.
      #
      # @param name [Symbol, String, Class] The type name or class to check
      # @param context [TypeContext, nil] The resolution context
      # @return [Boolean] true if type can be resolved
      def resolvable?(name, context)
        return true if @cache_backend.key?(type_cache_key(name, context))

        @delegate.resolvable?(name, context)
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
        @cache_backend.clear_context(context_id)
      end

      # Clear all caches.
      #
      # @return [void]
      def clear_all_caches
        @cache_backend.clear
      end

      # Get cache statistics (useful for debugging/monitoring).
      #
      # @return [Hash] Cache statistics
      def cache_stats
        keys = @cache_backend.keys

        {
          size: keys.size,
          keys: keys,
        }
      end

      private

      # Composite cache key: `[context_id, name]` when a context is present,
      # otherwise the bare name (Symbol or Class). The bare form avoids one
      # Array allocation per resolution in the common single-register run;
      # it cannot collide with composite keys since Arrays and
      # Symbols/Classes never match as Hash keys. Keys belonging to the nil
      # context are therefore the non-Array ones (see the backends'
      # #clear_context).
      def type_cache_key(name, context)
        bare = name.is_a?(Class) ? name : name.to_sym
        cid = context_id_for(context)
        cid ? [cid, bare] : bare
      end

      # A nil context (e.g. a register ID that has no registered type
      # context) is a legitimate "no namespace" resolution; the cache
      # key just forgoes the namespace slot.
      def context_id_for(context)
        context&.id
      end
    end
  end
end
