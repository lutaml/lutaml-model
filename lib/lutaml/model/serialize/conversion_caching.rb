# frozen_string_literal: true

Lutaml::Model::RuntimeCompatibility.require_native("digest")

module Lutaml
  module Model
    module Serialize
      # Opt-in caching of format conversions in both directions:
      # deserialized whole objects and serialized output strings
      # (issue #267).
      #
      # A class declares `cache_conversions`; plain `from_<format>` and
      # `to_<format>` calls are then served from the store configured via
      # `Config.conversion_cache`. The store is duck-typed — anything
      # responding to `get(key)` and `set(key, value)` works.
      # `Lutaml::Store::BasicStore` (lutaml-store gem) is the recommended
      # backend; TTL, eviction, persistence and clearing are the store's
      # concern, and store exceptions propagate unchanged. Cache hits do
      # not emit Instrumentation events — the work did not happen.
      #
      # Semantics (deliberate):
      # - `from_*` hits return the same cached instance for identical
      #   input — across callers and threads. Treat results as read-only;
      #   classes whose callers mutate parse results must not opt in.
      # - Keys digest everything that determines the result: the input
      #   string (:from) or instance (:to), plus all options except
      #   :register (folded into the key as a resolved id). What cannot
      #   be digested bypasses instead of risking a wrong hit: non-String
      #   inputs (Pathname/IO — content lives elsewhere), non-Hash
      #   options (Psych/JSON generator protocol objects), and graphs
      #   Marshal refuses — e.g. instances parsed from XML hold native
      #   parser nodes for round-trip fidelity, so :to caching engages
      #   for programmatically built instances.
      # - Structural invalidation is not propagated: mutating a register's
      #   mappings or calling GlobalContext.clear_caches does not touch
      #   the store — clear or replace the store after such mutations.
      # - A hit returns before the wrapped body runs, so option-hash
      #   mutations the body performs on a miss (e.g. consuming :adapter)
      #   do not happen on a hit.
      # - Caching is disabled under Opal: keys need native Marshal/Digest.
      module ConversionCaching
        NATIVE_RUNTIME = !Lutaml::Model::RuntimeCompatibility.opal?

        def cache_conversions
          define_singleton_method(:conversion_caching_enabled?) { true }
        end

        def conversion_caching_enabled?
          false
        end

        private

        def with_conversion_cache(kind, format, source, options)
          store = conversion_cache_store(options)
          return yield unless store

          payload = conversion_cache_payload(kind, source, options)
          return yield unless payload

          key = conversion_cache_key(kind, format, payload, options)
          cached = store.get(key)
          return cached if cacheable_value?(kind, cached)

          result = yield
          store.set(key, result) if cacheable_value?(kind, result)
          result
        end

        def conversion_cache_store(options)
          unless NATIVE_RUNTIME && conversion_caching_enabled? &&
              options.is_a?(::Hash)
            return
          end

          Config.conversion_cache
        end

        def conversion_cache_payload(kind, source, options)
          return if kind == :from && !source.is_a?(::String)

          ::Marshal.dump([source, options.except(:register)])
        rescue ::TypeError
          nil
        end

        # The key pins everything the payload digest does not: direction,
        # class identity (name plus object_id — same-named classes can
        # coexist, see TransformationRegistry's keys), format, register,
        # and resolved adapter.
        def conversion_cache_key(kind, format, payload, options)
          register = extract_register_id(options[:register])
          adapter = AdapterResolver.adapter_for(format)
          digest = ::Digest::SHA256.hexdigest(payload)

          "#{kind}:#{name}/#{object_id}:#{format}:#{register}:#{adapter}:#{digest}"
        end

        # Gate for both serving and admitting cache values: a :from value
        # must be an instance of this model, a :to value a serialized
        # String. Anything else — a store that JSON-marshals values back
        # into hashes, Array results from multi-document formats, nil —
        # is neither served nor stored.
        def cacheable_value?(kind, value)
          kind == :from ? value.is_a?(self) : value.is_a?(::String)
        end
      end
    end
  end
end
