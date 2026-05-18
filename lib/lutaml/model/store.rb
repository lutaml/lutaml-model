# frozen_string_literal: true

require "weakref"

module Lutaml
  module Model
    class Store
      # Compact dead WeakRef shells after this many entries per class bucket.
      COMPACTION_THRESHOLD = 1000

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
      end

      def register(object)
        model_key = object.class.to_s
        refs = @store[model_key]
        refs << WeakRef.new(object)

        compact_if_needed(refs)

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

        dereference(entry)
      end

      def clear
        @store = ::Hash.new { |hash, key| hash[key] = [] }
        @index = {}
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

      def compact_if_needed(refs)
        return unless refs.size > COMPACTION_THRESHOLD

        refs.reject! do |ref|
          !ref.weakref_alive?
        rescue WeakRef::RefError
          true
        end
      end
    end
  end
end
