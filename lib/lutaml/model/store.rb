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
        # Lazy index: built on first resolve for a given (class, key) pair.
        # Key: [class_name, reference_method] → { value => WeakRef(object) }
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
        index_key = [model_key, reference_key]

        # Build index lazily on first resolve for this (class, key) pair
        unless @index.key?(index_key)
          ensure_index(index_key, model_key,
                       reference_key)
        end

        # O(1) indexed lookup
        entry = @index[index_key][reference_value]
        return nil unless entry

        begin
          entry.__getobj__ if entry.weakref_alive?
        rescue WeakRef::RefError
          nil
        end
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

      # Build index for a (model_class, reference_key) pair by scanning existing instances.
      def ensure_index(index_key, model_key, reference_key)
        entries = @index[index_key] = {}
        @store[model_key]&.each do |ref|
          obj = ref.__getobj__
          value = obj.public_send(reference_key)
          entries[value] = WeakRef.new(obj) if value
        rescue WeakRef::RefError
          next
        end
      end

      # Update indices that already exist for this model class.
      def update_existing_indices(object, model_key)
        @index.each do |index_key, entries|
          next unless index_key[0] == model_key

          key_method = index_key[1]
          value = object.public_send(key_method)
          entries[value] = WeakRef.new(object) if value
        rescue WeakRef::RefError
          next
        end
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
