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

      # Local-name -> [attributes] index over one element's attributes,
      # built on first lenient lookup (TODO.max-perf/08) and memoized per
      # element for the life of the session. The URI-form attribute
      # conversion and the lenient fallback used to rescan every
      # attribute per rule per element (the ISO-13849 pathology);
      # elements are parse-frozen, so each index builds at most once.
      def element_local_attribute_index(element)
        @element_local_attribute_index ||= {}.compare_by_identity
        @element_local_attribute_index[element] ||= begin
          # Plain hash: a miss must stay a nil lookup, not allocate an
          # empty default array — misses dominate (the ISO-13849 shape
          # resolves ~390k lenient lookups that match nothing).
          index = {}
          element.attributes.each_value do |attr|
            local_names(attr).each do |key|
              entries = (index[key] ||= [])
              entries << attr unless entries.include?(attr)
            end
          end
          index
        end
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

def local_names(attr)
  colon = attr.name.rindex(":")
  split_local = colon ? attr.name[(colon + 1)..] : attr.name
  [attr.unprefixed_name, split_local].compact.uniq
end
