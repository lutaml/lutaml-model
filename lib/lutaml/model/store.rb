# frozen_string_literal: true

# Opal has no `weakref` stdlib; runtime_compatibility.rb provides a stub.
require "weakref" unless Lutaml::Model.opal?

module Lutaml
  module Model
    class Store
      # Compact dead index entries once a class bucket grows past this size.
      COMPACTION_THRESHOLD = 1000

      # Once the threshold is exceeded, only compact every Nth subsequent
      # register call. Amortises the O(N) prune over N inserts so
      # register stays O(1) per call rather than O(N) per call (O(N^2)
      # cumulatively for the class).
      COMPACTION_INTERVAL = 1000

      WeakBucket = if Lutaml::Model.opal?
                     # Opal has neither WeakRef nor ObjectSpace::WeakMap; documents in
                     # the browser are small, so strong references are the fallback.
                     ::Hash
                   else
                     # CRuby: WeakMap holds keys weakly with zero Ruby-level
                     # allocation per insert and no per-object finalizer — the WeakRef
                     # approach allocated one finalizer-registering object per
                     # instance (lutaml-model#695) and dominated GC cycles on
                     # instance-heavy parses.
                     ::ObjectSpace::WeakMap
                   end

      class << self
        def instance
          @instance ||= new
        end

        # lutaml-model#808: Ruby 3.3's GC has a WeakMap-mark hazard under
        # heavy insert churn (freed slot dereferenced at wmap mark time).
        # Registration is only ever consumed by `ref:` resolution — when
        # no Reference-typed attribute exists anywhere, nothing can
        # resolve, so registration is skipped entirely and the WeakMap
        # stays quiet. Set the first time an attribute with a Reference
        # type is defined.
        # Not memoized `||=` — the setter flips it to true for the
        # process lifetime and reads must see that.
        def reference_types_in_use?
          @reference_types_in_use ? true : false
        end

        def reference_types_in_use!
          @reference_types_in_use = true
        end

        def reset!
          @instance = new
        end

        def register(object)
          return unless reference_types_in_use?

          instance.register(object)
        end

        def resolve(model_class, reference_key, reference_value)
          instance.resolve(model_class, reference_key, reference_value)
        end

        def clear
          instance.clear
        end

        def store
          instance.store
        end
      end

      def initialize
        # WeakMap-based buckets: value presence marks liveness, no
        # per-instance allocation (lutaml-model#695).
        @store = ::Hash.new { |hash, key| hash[key] = WeakBucket.new }
        # Nested index: { model_key => { reference_key => { value => object } } }
        # Grouped by model_key so register only iterates this class's own indices.
        @index = {}
        @inserts_since_compaction = ::Hash.new(0)
        @compaction_count = 0
      end

      def register(object)
        model_key = object.class.to_s
        @store[model_key][object] = true
        @inserts_since_compaction[model_key] += 1

        compact_if_needed(model_key)

        update_existing_indices(object, model_key)
      end

      def resolve(model_class, reference_key, reference_value)
        model_key = model_class.to_s
        model_indices = @index[model_key]

        unless model_indices&.key?(reference_key)
          model_indices = ensure_model_index(model_key)
          build_index(model_indices, model_key, reference_key)
        end

        entry = model_indices[reference_key][reference_value]
        return nil unless entry

        obj = dereference(entry)
        model_indices[reference_key].delete(reference_value) unless obj
        obj
      end

      def live_objects(model_key)
        bucket = @store[model_key]
        return [] unless bucket

        live_objects_for(bucket)
      end

      def clear
        @store = ::Hash.new { |hash, key| hash[key] = WeakBucket.new }
        @index = {}
        @inserts_since_compaction = ::Hash.new(0)
        @compaction_count = 0
      end

      def store
        @store.transform_values { |refs| live_objects_for(refs) }
      end

      def refs_for(model_key)
        LiveView.new(self, model_key)
      end

      def inserts_since_compaction
        @inserts_since_compaction
      end

      def compaction_count
        @compaction_count
      end

      def index_entry_count(model_key)
        @index[model_key]&.sum { |_reference_key, entries| entries.size } || 0
      end

      private

      def ensure_model_index(model_key)
        @index[model_key] ||= {}
      end

      # Build index for a (model_class, reference_key) pair by scanning
      # live instances. Index values hold WeakRefs: the index must not
      # pin objects (only the rare classes with resolved reference keys
      # pay this; the per-instance bucket stays allocation-free WeakMap).
      def build_index(model_indices, model_key, reference_key)
        entries = model_indices[reference_key] = {}
        each_live(model_key) do |obj|
          value = obj.public_send(reference_key)
          entries[value] = WeakRef.new(obj) if value
        end
      end

      # Update indices that already exist for this model class only.
      # O(K) where K = number of reference keys indexed for this class,
      # not O(N×K) across all classes.
      def update_existing_indices(object, model_key)
        model_indices = @index[model_key]
        return unless model_indices

        model_indices.each_key do |reference_key|
          value = object.public_send(reference_key)
          model_indices[reference_key][value] = WeakRef.new(object) if value
        end
      end

      def dereference(entry)
        entry.__getobj__ if entry.weakref_alive?
      rescue WeakRef::RefError
        nil
      end

      def compact_if_needed(model_key)
        return unless @inserts_since_compaction[model_key] >= COMPACTION_INTERVAL

        @inserts_since_compaction[model_key] = 0
        @compaction_count += 1
        prune_index(model_key)
      end

      def prune_index(model_key)
        model_indices = @index[model_key]
        return unless model_indices

        model_indices.delete_if do |_reference_key, entries|
          entries.delete_if do |_value, ref|
            !ref.weakref_alive?
          rescue WeakRef::RefError
            true
          end
          entries.empty?
        end
      end

      def each_live(model_key, &block)
        @store[model_key]&.each_key(&block)
      end

      def live_objects_for(bucket)
        # WeakMap#each_key requires a block on CRuby; WeakMap#each
        # yields key/value pairs, and Hash buckets enumerate the same
        # way (value is `true` for WeakMap, the object for the Opal
        # fallback keyed by object identity).
        bucket.map { |key, _value| key }
      end

      # Array-shaped live view over a class's WeakMap bucket, for
      # specs/debugging (refs_for used to expose the raw array).
      class LiveView
        include Enumerable

        def initialize(store, model_key)
          @store = store
          @model_key = model_key
        end

        def each(&block)
          @store.live_objects(@model_key).each(&block)
        end

        def size
          @store.live_objects(@model_key).size
        end
      end
    end
  end
end
