# frozen_string_literal: true

module Lutaml
  module Xml
    # Per-parse context threaded through ModelTransform's mapping passes.
    #
    # Bundles everything one data_to_model call needs — the parsed doc, the
    # instance under construction, the effective register, and the flags
    # derived from them — so apply_xml_mapping and value_for_rule take one
    # object instead of a growing positional parameter list. Memoizes the
    # per-parse lookups (mapping, namespace class, adopted document
    # namespace) that every rule would otherwise recompute.
    class ParseSession
      attr_reader :doc, :instance, :options, :register

      def initialize(doc, instance, options, register)
        @doc = doc
        @instance = instance
        @options = options
        @register = register
      end

      def instance_is_serialize
        @instance_is_serialize ||= instance.is_a?(::Lutaml::Model::Serialize)
      end

      def model_class
        @model_class ||= instance.class
      end

      def xml_mapping
        @xml_mapping ||= model_class.mappings_for(:xml, register)
      end

      # The document's own namespace when it differs from the model's
      # bound namespace (lenient, out-of-namespace documents). Adopted as
      # an implicit alias for element matching (lutaml-model#754).
      def adopted_namespace_uri
        @adopted_namespace_uri ||=
          instance_is_serialize ? instance.original_namespace_uri : nil
      end

      # Namespace URIs accepted for children of this model: the model's
      # namespace URIs plus the adopted document namespace when present.
      def model_namespace_uris
        @model_namespace_uris ||=
          begin
            ns_class = instance_is_serialize ? xml_mapping&.namespace_class : nil
            uris = ns_class&.all_uris
            adopted = adopted_namespace_uri
            if ns_class && adopted && !uris&.include?(adopted)
              uris = (uris || []) + [adopted]
            end
            uris
          end
      end
    end
  end
end
