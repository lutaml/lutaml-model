# frozen_string_literal: true

module Lutaml
  module Rdf
    class MappingRule
      attr_reader :predicate_name, :namespace, :to, :lang_tagged, :uri_reference

      def initialize(predicate_name, namespace:, to:, lang_tagged: false,
                     uri_reference: false)
        validate!(predicate_name, namespace, to)
        if lang_tagged && uri_reference
          raise ArgumentError,
                "lang_tagged and uri_reference are mutually exclusive"
        end

        @predicate_name = predicate_name.to_s.freeze
        @namespace = namespace
        @to = to
        @lang_tagged = lang_tagged
        @uri_reference = uri_reference
      end

      def kind
        if uri_reference
          :uri_reference
        elsif lang_tagged
          :lang_tagged
        else
          :plain
        end
      end

      def uri
        @namespace[@predicate_name]
      end

      def prefixed_name
        @namespace.prefixed(@predicate_name)
      end

      private

      def validate!(name, namespace_class, target)
        raise ArgumentError, "predicate_name is required" unless name
        unless namespace_class.is_a?(Class) && namespace_class < Lutaml::Rdf::Namespace
          raise ArgumentError, "namespace must be a Rdf::Namespace subclass"
        end
        raise ArgumentError, ":to is required" unless target
      end
    end
  end
end
