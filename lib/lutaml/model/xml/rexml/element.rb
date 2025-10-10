# frozen_string_literal: true

require_relative "../xml_element"
require_relative "../xml_namespace"

module Lutaml
  module Model
    module Xml
      module Rexml
        class Element < XmlElement
          attr_accessor :target_encoding

          def initialize(node, parent: nil, target_encoding: nil)
            @target_encoding = target_encoding || (parent.is_a?(Element) ? parent.target_encoding : nil)

            text = case node
                   when Moxml::Element
                     namespace_name = node.namespace&.prefix
                     add_namespaces(node)
                     children = parse_children(node)
                     attributes = node_attributes(node)
                     @root = node
                     node.text
                   when Moxml::Text, Moxml::Cdata
                     node.content
                   end

            name = RexmlAdapter.name_of(node)
            super(
              node,
              Hash(attributes),
              Array(children),
              text,
              name: name,
              parent_document: parent,
              namespace_prefix: namespace_name,
            )
          end

          def text?
            children.empty? && text&.length&.positive?
          end

          def text
            txt = super || cdata || @text
            # Convert text to target encoding if needed
            if txt && @target_encoding && @target_encoding != "UTF-8"
              if txt.is_a?(Array)
                # Handle array of text fragments (mixed content)
                txt = txt.map do |fragment|
                  if fragment.is_a?(String) && fragment.encoding.to_s == "UTF-8"
                    fragment.encode(@target_encoding)
                  else
                    fragment
                  end
                end
              elsif txt.is_a?(String) && txt.encoding.to_s == "UTF-8"
                txt = txt.encode(@target_encoding)
              end
            end
            txt
          end

          def to_xml(builder = Builder::Rexml.build)
            # For text and cdata nodes, return the text content directly
            return text if ["text", "#cdata-section"].include?(name)

            build_xml(builder).to_xml
          end

          def build_xml(builder = Builder::Rexml.build)
            if name == "text"
              builder.add_text(builder.current_node, text)
            elsif name == "#cdata-section"
              builder.add_text(builder.current_node, text, cdata: true)
            else
              builder.create_and_add_element(name, attributes: build_attributes_hash) do |xml|
                children.each do |child|
                  child.build_xml(xml)
                end
              end
            end

            builder
          end

          def inner_xml
            children.map(&:to_xml).join
          end

          private

          def parse_children(node)
            return [] unless node.children

            node.children.filter_map do |child|
              next if RexmlAdapter::TEXT_CLASSES.include?(child.class) && child.content.empty?

              Element.new(child, parent: self)
            end
          end

          def node_attributes(node)
            return {} unless node.respond_to?(:attributes)

            attributes = {}
            begin
              # Try to get the raw REXML attributes directly
              if node.respond_to?(:native) && node.native.respond_to?(:attributes)
                rexml_node = node.native
                rexml_node.attributes.each do |name, value|
                  # Skip namespace declarations
                  next if name == "xmlns" || name.start_with?("xmlns:")

                  # Extract namespace information from the attribute name
                  namespace_prefix = nil
                  attr_name = name
                  namespace_uri = nil

                  if name.include?(":")
                    namespace_prefix, attr_name = name.split(":", 2)
                    # Look up the namespace URI from the element's namespaces
                    namespace_uri = namespaces[namespace_prefix]&.uri
                  end

                  attributes[name] = XmlAttribute.new(
                    attr_name,
                    value,
                    namespace: namespace_uri,
                    namespace_prefix: namespace_prefix,
                  )
                end
              elsif node.attributes && !node.attributes.empty?
                # Fallback to moxml attributes (may fail due to bug)
                node.attributes.each do |attr|
                  next if attr_is_namespace?(attr)

                  attr_name = if attr.namespace
                                "#{attr.namespace.prefix}:#{attr.name}"
                              else
                                attr.name
                              end

                  attributes[attr_name] = XmlAttribute.new(
                    attr_name,
                    attr.value,
                    namespace: attr.namespace&.uri,
                    namespace_prefix: attr.namespace&.prefix,
                  )
                end
              end
            rescue StandardError
              # Handle attribute parsing issues
            end
            attributes
          end

          def add_namespaces(node)
            return unless node.respond_to?(:namespaces) && node.namespaces

            node.namespaces.each do |namespace|
              add_namespace(XmlNamespace.new(namespace.uri, namespace.prefix))
            end
          end

          def build_attributes_hash
            attrs = {}
            attributes.each do |name, attr|
              attrs[name] = attr.value
            end
            attrs
          end

          def attr_is_namespace?(attr)
            attribute_is_namespace?(attr.name) ||
              namespaces[attr.name]&.uri == attr.value
          end
        end
      end
    end
  end
end
