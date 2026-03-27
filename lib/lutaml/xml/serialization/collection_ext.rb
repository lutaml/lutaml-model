# frozen_string_literal: true

module Lutaml
  module Xml
    module Serialization
      # XML-specific overrides for Collection class methods.
      #
      # Prepended into Collection's singleton class when XML is loaded.
      # Provides XML-specific no_root handling for collections.
      module CollectionExt
        # XML is a structured (tree-based) format
        def collection_structured_format?(format)
          return super unless format == :xml

          true
        end

        # XML handles no_root serialization specially
        def collection_no_root_to?(format)
          return super unless format == :xml

          true
        end

        # XML no_root serialization: serialize each mapping separately
        def collection_no_root_to(format, mappings, instance, options)
          return super unless format == :xml

          mappings.mappings.map do |mapping|
            serialize_for_mapping(mapping, instance, format, options)
          end.join("\n")
        end

        # XML no_root: wrap raw XML in a fake root tag before parsing
        def wrap_no_root_input(format, mappings, data)
          return super unless format == :xml

          tag_name = mappings.find_by_to!(instance_name).name
          "<#{tag_name}>#{data}</#{tag_name}>"
        end

        private

        def serialize_for_mapping(mapping, instance, format, options)
          options[:tag_name] = mapping.name

          attr_value = instance.public_send(mapping.to)
          return if attr_value.nil? || attr_value.empty?

          # Handle custom Collection classes - extract the actual items array
          if attr_value.is_a?(Lutaml::Model::Collection)
            attr_value = attr_value.collection
          end

          attr_value = [attr_value] unless attr_value.is_a?(Array)
          attr_value.map { |v| v.public_send(:"to_#{format}", options) }
        end
      end
    end
  end
end
