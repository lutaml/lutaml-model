# frozen_string_literal: true

module Lutaml
  module Model
    # Step collector for the `evolution from:` DSL (#265). Each declared
    # step is a closure applied in declaration order to the source
    # document's wire hash; the evolved hash is then parsed by the
    # target model. All steps are wire-level: they relocate, merge and
    # drop keys of the old document — the model pipeline never sees a
    # half-migrated shape.
    class EvolutionSteps
      def initialize
        @steps = []
      end

      attr_reader :steps

      # Accept a document written with a former wire name for the
      # current attribute. The current name wins when both appear.
      def wire_rename(from_key, to:)
        from_key = from_key.to_s
        to = to.to_s
        @steps << lambda do |hash|
          next hash unless hash.key?(from_key)

          hash[to] = hash.delete(from_key) unless hash.key?(to)
          hash
        end
      end

      # Relocate a former top-level key into a nested position, given
      # as a dot path ("metadata.name") or an array of segments.
      # Intermediate objects are created as needed.
      def wire_move(from_key, to:)
        path = to.is_a?(::Array) ? to.map(&:to_s) : to.split(".").map(&:to_s)
        from_key = from_key.to_s
        @steps << lambda do |hash|
          value = hash.delete(from_key)
          next hash if value.nil?

          target = hash
          path[0...-1].each do |segment|
            target = (target[segment] ||= {})
          end
          target[path[-1]] = value
          hash
        end
      end

      # Combine former keys into one. With `with:`, it receives the
      # source values in declared order and returns the new value;
      # without it, the sources must all be hashes and are merged in
      # declared order.
      def wire_merge(from_keys, to:, with: nil)
        keys = from_keys.map(&:to_s)
        to = to.to_s
        @steps << lambda do |hash|
          values = keys.map { |key| hash.delete(key) }
          hash[to] =
            if with
              with.call(*values)
            elsif values.all?(::Hash)
              values.reduce { |merged, value| merged.merge(value) }
            else
              raise ArgumentError,
                    "wire_merge requires with: when the merged values " \
                    "are not all hashes"
            end
          hash
        end
      end

      # Retire former keys explicitly. Documentation as much as
      # behavior: an undeclared unknown key keeps the map_unmapped /
      # drop semantics; a declared one states the vocabulary removed it.
      def wire_drop(*keys)
        dropped = keys.map(&:to_s)
        @steps << lambda do |hash|
          dropped.each { |key| hash.delete(key) }
          hash
        end
      end
    end
  end
end
