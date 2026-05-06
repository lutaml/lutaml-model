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
        @rdf_type = nil
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
        @rdf_type = value
      end

      def predicate(name, namespace:, to:, lang_tagged: false)
        @rdf_predicates << Lutaml::Rdf::MappingRule.new(
          name,
          namespace: namespace,
          to: to,
          lang_tagged: lang_tagged,
        )
      end

      def members(attr_name)
        @rdf_members << Lutaml::Rdf::MemberRule.new(attr_name)
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
        self.class.new.tap do |new_mapping|
          new_mapping.instance_variable_set(:@namespace_set, @namespace_set)
          new_mapping.instance_variable_set(:@rdf_subject, @rdf_subject)
          new_mapping.instance_variable_set(:@rdf_type, @rdf_type)
          new_mapping.instance_variable_set(:@rdf_predicates,
                                            @rdf_predicates.dup)
          new_mapping.instance_variable_set(:@rdf_members, @rdf_members.dup)
        end
      end
    end
  end
end
