# frozen_string_literal: true

module Lutaml
  module Rdf
    class Transform < Lutaml::Model::Transform
      protected

      def resolve_subject_uri(mapping, instance)
        mapping.rdf_subject&.call(instance)
      end

      def resolve_type_uri(mapping)
        return unless mapping.rdf_type

        mapping.namespace_set.resolve_compact_iri(mapping.rdf_type)
      end

      def resolve_type_compact(mapping)
        mapping.rdf_type
      end

      def build_instance(attrs, options)
        child_register = Lutaml::Model::Register.resolve_for_child(
          model_class, lutaml_register
        )
        instance = model_class.new(attrs.merge(lutaml_register: child_register))
        root_and_parent_assignment(instance, options)
        instance
      end

      def extract_language(value)
        value.language_tag if value.is_a?(Lutaml::Rdf::LanguageTagged)
      end
    end
  end
end
