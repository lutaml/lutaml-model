# frozen_string_literal: true

module Lutaml
  module Xml
    module NestedCollectionAttribute
      private

      def nested_collection_attribute_node(child, attr, attr_type, register)
        return child unless nested_collection_attribute?(attr, attr_type)

        collection_mapping = attr_type.mappings_for(:xml, register)
        root_name = collection_mapping&.element_name ||
          collection_mapping&.root_element
        return child if root_name.nil?

        root_name = root_name.to_s
        return child if root_name.empty?
        return child if xml_element_matches_name?(child, root_name,
                                                  collection_mapping)

        child.element_children.find do |nested_child|
          xml_element_matches_name?(nested_child, root_name,
                                    collection_mapping)
        end || child
      end

      def nested_collection_attribute_element?(rule, value, child_element)
        nested_collection_attribute_value?(rule, value) &&
          rule.serialized_name != child_element.name
      end

      def nested_collection_attribute_value?(rule, value)
        value.is_a?(::Lutaml::Model::Collection) &&
          nested_collection_attribute_type?(rule.attribute_type) &&
          !rule.collection?
      end

      def nested_collection_wrapper_prefix(rule, options)
        parent_model = options[:current_model]
        return unless parent_model.is_a?(::Lutaml::Model::Serialize)

        prefix = parent_model.xml_ns_prefixes&.[](rule.attribute_name)
        prefix unless prefix.to_s.empty?
      end

      def explicit_namespace_prefix(element)
        return unless element.namespace_prefix_explicit &&
          element.namespace_prefix

        element.namespace_prefix
      end

      def nested_collection_attribute?(attr, attr_type)
        attr&.singular? && nested_collection_attribute_type?(attr_type)
      end

      def nested_collection_attribute_type?(attr_type)
        attr_type.is_a?(Class) &&
          attr_type <= ::Lutaml::Model::Collection
      end

      def xml_element_matches_name?(element, name, mapping)
        element.unprefixed_name == name &&
          xml_element_matches_namespace?(element.namespace_uri, mapping)
      end

      def xml_element_matches_namespace?(namespace_uri, mapping)
        namespace_class = mapping&.namespace_class
        mapping_uri = mapping&.namespace_uri
        return namespace_uri.nil? unless namespace_class || mapping_uri
        return true if mapping_uri && namespace_uri == mapping_uri

        if namespace_class.respond_to?(:all_uris)
          namespace_class.all_uris.include?(namespace_uri)
        else
          namespace_uri == namespace_class&.uri
        end
      end
    end
  end
end
