# frozen_string_literal: true

module Lutaml
  module Rdf
    class NamespaceSet
      include Enumerable

      def initialize(*namespace_classes)
        @by_prefix = {}
        namespace_classes.each { |ns| add(ns) }
      end

      def add(namespace_class)
        pfx = namespace_class.prefix
        if @by_prefix.key?(pfx) && @by_prefix[pfx] != namespace_class
          raise ArgumentError,
                "Prefix '#{pfx}' conflicts: #{@by_prefix[pfx].name} vs #{namespace_class.name}"
        end
        @by_prefix[pfx] = namespace_class
        self
      end

      def [](prefix)
        @by_prefix[prefix]
      end

      def resolve_compact_iri(compact_iri)
        Namespace.resolve_compact_iri(compact_iri, to_a)
      end

      def compact(full_uri)
        each do |ns|
          next unless full_uri.start_with?(ns.uri)

          local = full_uri.delete_prefix(ns.uri)
          return ns.prefixed(local)
        end
        nil
      end

      def each(&)
        @by_prefix.each_value(&)
      end

      def size
        @by_prefix.size
      end

      def empty?
        @by_prefix.empty?
      end

      def to_a
        @by_prefix.values
      end

      def to_hash
        @by_prefix.transform_values(&:uri)
      end

      def merge(other_set)
        return self if equal?(other_set)

        other_set.each { |ns| add(ns) }
        self
      end
    end
  end
end
