# frozen_string_literal: true

module Lutaml
  module Rdf
    class Transform < Lutaml::Model::Transform
      def resolve_subject_uri(mapping, instance)
        mapping.rdf_subject&.call(instance)
      end

      def resolve_single_type_uri(mapping, type_value)
        mapping.namespace_set.resolve_compact_iri(type_value)
      end

      def resolve_type_uris(mapping)
        return [] unless mapping.rdf_type.any?

        mapping.rdf_type.map { |t| resolve_single_type_uri(mapping, t) }
      end

      def each_member(instance, member_rule, &)
        collection = Array(instance.public_send(member_rule.attr_name))
        collection.each(&)
      end

      def member_mapping_for(member, format)
        member.class.mappings[format]
      end

      def extract_language(value)
        value.language_tag if value.is_a?(Lutaml::Rdf::LanguageTagged)
      end

      protected

      def build_instance(attrs, options)
        child_register = Lutaml::Model::Register.resolve_for_child(
          model_class, lutaml_register
        )
        instance = model_class.new(attrs.merge(lutaml_register: child_register))
        root_and_parent_assignment(instance, options)
        instance
      end
    end
  end
end
