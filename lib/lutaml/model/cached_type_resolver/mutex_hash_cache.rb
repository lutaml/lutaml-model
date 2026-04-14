# frozen_string_literal: true

module Lutaml
  module Model
    class CachedTypeResolver
      # Hash-backed cache that only relies on Mutex semantics available on Opal.
      class MutexHashCache
        def initialize(store: {}, mutex: Mutex.new)
          @store = store
          @mutex = mutex
        end

        def fetch_or_store(cache_key)
          found = false
          cached_value = @mutex.synchronize do
            if @store.key?(cache_key)
              found = true
              @store[cache_key]
            end
          end
          return cached_value if found

          value = yield

          @mutex.synchronize do
            @store[cache_key] = value unless @store.key?(cache_key)
            @store[cache_key]
          end
        end

        def key?(cache_key)
          @mutex.synchronize { @store.key?(cache_key) }
        end

        def clear_context(context_id)
          @mutex.synchronize do
            @store.delete_if { |key, _| key[0] == context_id }
          end
        end

        def clear
          @mutex.synchronize { @store.clear }
        end

        def keys
          @mutex.synchronize { @store.keys.dup }
        end
      end
    end
  end
end
