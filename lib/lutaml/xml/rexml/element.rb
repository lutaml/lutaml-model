# frozen_string_literal: true

module Lutaml
  module Xml
    module Rexml
      class Element < XmlElement
        # Use NamespaceData for adapter-internal namespace data
        NamespaceData = Lutaml::Xml::Adapter::NamespaceData

        attr_accessor :target_encoding

        def initialize(node, parent: nil, target_encoding: nil)
          @target_encoding = target_encoding || (parent.is_a?(Element) ? parent.target_encoding : nil)

          # Determine node type from Moxml classification
          node_type = case node
                      when Moxml::Text then :text
                      when Moxml::Cdata then :cdata
                      else :element
                      end

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

          name = Lutaml::Xml::Adapter::RexmlAdapter.name_of(node)
          super(
            node,
            Hash(attributes),
            Array(children),
            text,
            name: name,
            parent_document: parent,
            namespace_prefix: namespace_name,
            node_type: node_type
          )
        end

        def text?
          # Text nodes have node_type == :text or :cdata
          [:text, :cdata].include?(@node_type)
        end

        def text
          txt = super || cdata || @text
          convert_text_encoding(txt)
        end

        def to_xml(builder = Builder::Rexml.build)
          # For text and cdata nodes, return the text content directly
          return text if text? || cdata?

          build_xml(builder).to_xml
        end

        def build_xml(builder = Builder::Rexml.build)
          if cdata?
            # CDATA sections
            builder.add_text(builder.current_node, text, cdata: true)
          elsif text? && !element?
            # Only actual text nodes (not elements named "text")
            builder.add_text(builder.current_node, text)
          else
            # Regular elements (including those named "text")
            builder.create_and_add_element(name,
                                           attributes: build_attributes_hash) do |xml|
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
            next if Lutaml::Xml::Adapter::RexmlAdapter::TEXT_CLASSES.include?(child.class) && child.content.empty?

            Element.new(child, parent: self)
          end
        end

        def node_attributes(node)
          return {} unless node.native.respond_to?(:attributes)

          parse_native_attributes(node.native)
        end

        def parse_native_attributes(rexml_node)
          attributes = {}
          rexml_node.attributes.each do |name, value|
            next if name == "xmlns" || name.start_with?("xmlns:")

            attributes[name] = create_xml_attribute(name, value)
          end
          attributes
        end

        def create_xml_attribute(name, value)
          attr_name, namespace_prefix, namespace_uri = parse_attribute_namespace(name)

          XmlAttribute.new(attr_name, value,
                           namespace: namespace_uri,
                           namespace_prefix: namespace_prefix)
        end

        def parse_attribute_namespace(name)
          return [name, nil, nil] unless name.include?(":")

          namespace_prefix = name.split(":").first
          namespace_uri = namespaces[namespace_prefix]&.uri

          [name, namespace_prefix, namespace_uri]
        end

        def create_moxml_attribute(attr)
          attr_name = if attr.namespace&.prefix
                        "#{attr.namespace.prefix}:#{attr.name}"
                      else
                        attr.name
                      end

          XmlAttribute.new(attr_name, attr.value,
                           namespace: attr.namespace&.uri,
                           namespace_prefix: attr.namespace&.prefix)
        end

        def add_namespaces(node)
          return unless node.respond_to?(:namespaces) && node.namespaces

          node.namespaces.each do |namespace|
            add_namespace(NamespaceData.new(namespace.uri, namespace.prefix))
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

        def convert_text_encoding(txt)
          return txt unless txt && @target_encoding && @target_encoding != "UTF-8"

          return convert_array_encoding(txt) if txt.is_a?(Array)
          return convert_string_encoding(txt) if txt.is_a?(String)

          txt
        end

        def convert_array_encoding(array)
          array.map do |fragment|
            fragment.is_a?(String) ? convert_string_encoding(fragment) : fragment
          end
        end

        def convert_string_encoding(string)
          return string unless string.encoding.to_s == "UTF-8"

          string.encode(@target_encoding)
        end
      end
    end
  end
end
