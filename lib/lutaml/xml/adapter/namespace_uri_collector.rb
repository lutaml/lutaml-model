# frozen_string_literal: true

require "set"

module Lutaml
  module Xml
    module Adapter
      # Collects original namespace URIs from a model tree for namespace alias support.
      #
      # When parsing XML with alias URIs (e.g., "http://.../") against a namespace
      # class with canonical URI (e.g., "http://.../reqif.xsd"), the original alias
      # URI is stored on the model instance as @__xml_original_namespace_uri.
      # This module collects all such mappings from the model tree.
      module NamespaceUriCollector
        # @param model [Object] the model instance to walk
        # @param mapping [Xml::Mapping, nil] the mapping for the model
        # @return [Hash<String, String>] Mapping of canonical URI => original alias URI
        def collect_original_namespace_uris(model, mapping = nil)
          original_uris = {}
          return original_uris unless model

          collect_from_model(model, mapping, original_uris, Set.new)
          original_uris
        end

        private

        def collect_from_model(model, mapping, original_uris, visited)
          return unless model.is_a?(::Lutaml::Model::Serialize)
          return if visited.include?(model.object_id)

          visited.add(model.object_id)

          if model.respond_to?(:original_namespace_uri) && model.original_namespace_uri
            original_uri = model.original_namespace_uri
            if original_uri && !original_uri.empty?
              ns_class = model.class.mappings_for(:xml)&.namespace_class
              if ns_class && ns_class.uri != original_uri
                original_uris[ns_class.uri] = original_uri
              end
            end
          end

          return unless mapping

          attributes = model.class.attributes
          mapping.elements.each do |elem_rule|
            attr_def = attributes[elem_rule.to]
            next unless attr_def

            child_type = attr_def.type(Lutaml::Model::Config.default_register)
            next unless child_type.respond_to?(:<) && child_type < ::Lutaml::Model::Serializable

            child_mapping = child_type.mappings_for(:xml)
            next unless child_mapping

            child_instance = model.public_send(elem_rule.to) if model.respond_to?(elem_rule.to)

            if child_instance.is_a?(Array) || child_instance.is_a?(::Lutaml::Model::Collection)
              instances = child_instance.is_a?(::Lutaml::Model::Collection) ? child_instance.collection : child_instance
              instances.each do |item|
                collect_from_model(item, child_mapping, original_uris, visited)
              end
            elsif child_instance
              collect_from_model(child_instance, child_mapping, original_uris,
                                 visited)
            end
          end
        end
      end
    end
  end
end
