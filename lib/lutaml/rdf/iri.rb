# frozen_string_literal: true

module Lutaml
  module Rdf
    class Iri
      include Comparable

      attr_reader :value

      def initialize(uri_string)
        @value = uri_string.to_s.freeze
      end

      def expand(namespace_set)
        namespace_set.resolve_compact_iri(value)
      end

      def compact(namespace_set)
        namespace_set.compact(value)
      end

      def <=>(other)
        other.is_a?(self.class) ? value <=> other.value : nil
      end

      def ==(other)
        other.is_a?(self.class) && value == other.value
      end
      alias_method :eql?, :==

      def hash
        value.hash
      end

      def to_s
        value
      end

      def inspect
        "#<#{self.class.name} #{value}>"
      end
    end
  end
end
