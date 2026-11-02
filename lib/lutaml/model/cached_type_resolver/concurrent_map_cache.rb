# frozen_string_literal: true

require "concurrent"

module Lutaml
  module Model
    class CachedTypeResolver
      # Concurrent::Map-backed cache optimized for native Ruby runtimes.
      #
      # The value block runs outside an atomic compute section so nested type
      # resolution can re-enter the cache. Under concurrent misses, more than
      # one thread may compute; the first stored value wins.
      class ConcurrentMapCache
        def initialize(store: Concurrent::Map.new)
          @store = store
        end

        def fetch_or_store(cache_key)
          return @store[cache_key] if @store.key?(cache_key)

          value = yield
          @store.put_if_absent(cache_key, value)
          @store[cache_key]
        end

        def key?(cache_key)
          @store.key?(cache_key)
        end

        def clear_context(context_id)
          @store.each_key do |key|
            # Non-Array keys are the bare, nil-context form (see
            # CachedTypeResolver#type_cache_key).
            @store.delete(key) if (key.is_a?(Array) ? key[0] : nil) == context_id
          end
        end

        def clear
          @store.clear
        end

        def keys
          @store.keys
        end
      end
    end
  end
end
