# frozen_string_literal: true

module Lutaml
  module Rdf
    class MemberRule
      attr_reader :attr_name, :predicate_name, :namespace, :link

      def initialize(attr_name, predicate_name: nil, namespace: nil, link: nil)
        if predicate_name && !namespace
          raise ArgumentError,
                "namespace is required when predicate_name is provided"
        end

        if predicate_name && link
          raise ArgumentError,
                "predicate_name and link are mutually exclusive"
        end

        @attr_name = attr_name.to_sym
        @predicate_name = predicate_name
        @namespace = namespace
        @link = link
      end

      def linked?
        !!(@predicate_name || @link)
      end

      def linked_predicate_uri
        return nil unless @predicate_name

        @namespace[@predicate_name]
      end

      def link_predicate_for(member, resolver)
        return nil unless @link

        case @link
        when String
          resolver.call(@link)
        when Proc
          resolver.call(@link.call(member))
        end
      end

      def resolve_link_uri(member, resolver)
        if @predicate_name
          linked_predicate_uri
        elsif @link
          link_predicate_for(member, resolver)
        end
      end
    end
  end
end
