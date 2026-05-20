# frozen_string_literal: true

module Lutaml
  module Rdf
    class MemberRule
      attr_reader :attr_name, :predicate_name, :namespace

      def initialize(attr_name, predicate_name: nil, namespace: nil)
        if predicate_name && !namespace
          raise ArgumentError,
                "namespace is required when predicate_name is provided"
        end

        @attr_name = attr_name.to_sym
        @predicate_name = predicate_name
        @namespace = namespace
      end

      def linked?
        !!@predicate_name
      end

      def linked_predicate_uri
        return nil unless linked?

        @namespace[@predicate_name]
      end
    end
  end
end
