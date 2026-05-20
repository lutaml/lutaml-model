# frozen_string_literal: true

require "weakref"

module Lutaml
  module Model
    class Store
      # Compact dead WeakRef shells once a class bucket grows past this size.
      COMPACTION_THRESHOLD = 1000

      # Once the threshold is exceeded, only compact every Nth subsequent
      # register call. Amortises the O(N) reject! over N inserts so
      # register stays O(1) per call rather than O(N) per call (O(N^2)
      # cumulatively for the class).
      COMPACTION_INTERVAL = 1000

      class << self
        def instance
          @instance ||= new
        end

        def reset!
          @instance = new
        end

        def register(object)
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
        @store = ::Hash.new { |hash, key| hash[key] = [] }
        # Nested index: { model_key => { reference_key => { value => WeakRef(object) } } }
        # Grouped by model_key so register only iterates this class's own indices.
        @index = {}
        @inserts_since_compaction = ::Hash.new(0)
        @compaction_count = 0
      end

      def register(object)
        model_key = object.class.to_s
        refs = @store[model_key]
        refs << WeakRef.new(object)
        @inserts_since_compaction[model_key] += 1

        compact_if_needed(refs, model_key)

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

      def clear
        @store = ::Hash.new { |hash, key| hash[key] = [] }
        @index = {}
        @inserts_since_compaction = ::Hash.new(0)
        @compaction_count = 0
      end

      def store
        @store.transform_values do |refs|
          refs.each_with_object([]) do |ref, alive|
            alive << ref.__getobj__ if ref.weakref_alive?
          rescue WeakRef::RefError
            nil
          end
        end
      end

      def refs_for(model_key)
        @store[model_key]
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

      # Build index for a (model_class, reference_key) pair by scanning existing instances.
      def build_index(model_indices, model_key, reference_key)
        entries = model_indices[reference_key] = {}
        @store[model_key]&.each do |ref|
          obj = ref.__getobj__
          value = obj.public_send(reference_key)
          entries[value] = WeakRef.new(obj) if value
        rescue WeakRef::RefError
          next
        end
      end

      # Update indices that already exist for this model class only.
      # O(K) where K = number of reference keys indexed for this class,
      # not O(N×K) across all classes.
      def update_existing_indices(object, model_key)
        model_indices = @index[model_key]
        return unless model_indices

        model_indices.each do |reference_key, entries|
          value = object.public_send(reference_key)
          entries[value] = WeakRef.new(object) if value
        rescue WeakRef::RefError
          next
        end
      end

      def dereference(entry)
        entry.__getobj__ if entry.weakref_alive?
      rescue WeakRef::RefError
        nil
      end

      def compact_if_needed(refs, model_key)
        return unless refs.size > COMPACTION_THRESHOLD
        return unless @inserts_since_compaction[model_key] >= COMPACTION_INTERVAL

        @inserts_since_compaction[model_key] = 0
        @compaction_count += 1
        refs.reject! do |ref|
          !ref.weakref_alive?
        rescue WeakRef::RefError
          true
        end
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
    end
  end
end
