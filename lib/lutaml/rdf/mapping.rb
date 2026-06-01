# frozen_string_literal: true

module Lutaml
  module Rdf
    class Mapping < Lutaml::Model::Mapping
      attr_reader :namespace_set, :rdf_subject, :rdf_type, :rdf_predicates,
                  :rdf_members

      def initialize
        super
        @namespace_set = Lutaml::Rdf::NamespaceSet.new
        @rdf_subject = nil
        @rdf_type = []
        @rdf_predicates = []
        @rdf_members = []
      end

      def namespace(*namespace_classes)
        @namespace_set = Lutaml::Rdf::NamespaceSet.new(*namespace_classes)
      end

      def subject(&)
        @rdf_subject = Proc.new(&) if block_given?
      end

      def type(value)
        @rdf_type = Array(value)
      end

      def types(*values)
        @rdf_type = values.flatten
      end

      def has_types_or_predicates?
        @rdf_type.any? || @rdf_predicates.any?
      end

      def predicate(name, namespace:, to:, lang_tagged: false,
                    uri_reference: false)
        @rdf_predicates << Lutaml::Rdf::MappingRule.new(
          name,
          namespace: namespace,
          to: to,
          lang_tagged: lang_tagged,
          uri_reference: uri_reference,
        )
      end

      def members(attr_name, predicate_name: nil, namespace: nil, link: nil)
        @rdf_members << Lutaml::Rdf::MemberRule.new(
          attr_name,
          predicate_name: predicate_name,
          namespace: namespace,
          link: link,
        )
      end

      def mappings(_register_id = nil)
        @rdf_predicates
      end

      def finalize(_mapper_class); end

      def finalized?
        true
      end

      def map_element(name, to:)
        raise Lutaml::Model::IncorrectMappingArgumentsError,
              "RDF mappings use `predicate` instead of `map_element`. " \
              "Use `predicate :#{name}, namespace: MyNs, to: :#{to}` inside `rdf do`."
      end

      def deep_dup
        dup
      end

      def initialize_copy(source)
        super
        @rdf_type = source.rdf_type.dup
        @rdf_predicates = source.rdf_predicates.dup
        @rdf_members = source.rdf_members.dup
      end
    end
  end
end
