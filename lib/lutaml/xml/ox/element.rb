# frozen_string_literal: true

module Lutaml
  module Xml
    module Ox
      class Element < XmlElement
        # Use NamespaceData for adapter-internal namespace data
        NamespaceData = Lutaml::Xml::Adapter::NamespaceData

        def initialize(node, parent: nil, default_namespace: nil)
          explicit_no_namespace = false

          # Determine node type from Moxml classification
          node_type = case node
                      when Moxml::Text then :text
                      when Moxml::Cdata then :cdata
                      when Moxml::Comment then :comment
                      else :element
                      end

          text = case node
                 when Moxml::Element
                   namespace_name = node.namespace&.prefix

                   # Detect explicit xmlns="" for no namespace
                   has_empty_xmlns = node.namespaces.any? do |ns|
                     ns.prefix.nil? && ns.uri == ""
                   end

                   explicit_no_namespace = XmlElement.detect_explicit_no_namespace(
                     has_empty_xmlns: has_empty_xmlns,
                     node_namespace_nil: node.namespace.nil? || node.namespace&.uri == "",
                   )

                   add_namespaces(node)

                   default_namespace = node.namespace&.uri if parent.nil? && !namespace_name && node.namespace&.uri != ""

                   children = parse_children(node,
                                             default_namespace: default_namespace)
                   attributes = node_attributes(node)
                   @root = node
                   EncodingNormalizer.normalize_to_utf8(node.inner_text)
                 when Moxml::Text
                   EncodingNormalizer.normalize_to_utf8(node.content)
                 when Moxml::Cdata
                   EncodingNormalizer.normalize_to_utf8(node.native.respond_to?(:value) ? node.native.value : node.content)
                 when Moxml::Comment
                   EncodingNormalizer.normalize_to_utf8(node.content)
                 end

          name = Lutaml::Xml::Adapter::OxAdapter.name_of(node)
          super(
            name,
            Hash(attributes),
            Array(children),
            text,
            name: name,
            parent_document: parent,
            namespace_prefix: namespace_name,
            default_namespace: default_namespace,
            explicit_no_namespace: explicit_no_namespace,
            node_type: node_type
          )
        end

        def text?
          # Text nodes have node_type == :text or :cdata
          %i[text cdata].include?(@node_type)
        end

        def text
          super || @text
        end

        def to_xml(builder = nil)
          builder ||= Builder::Ox.build
          build_xml(builder).xml.to_s.chomp
        end

        def build_xml(builder = nil)
          builder ||= Builder::Ox.build

          if comment?
            # Comment nodes - output as XML comments
            builder.add_comment(@text)
          elsif cdata?
            # CDATA sections - output as CDATA-wrapped text
            builder.add_text(builder, @text, cdata: true)
          elsif text? && !element?
            # Only actual text nodes (not elements named "text")
            builder.add_text(builder, @text)
          else
            # Regular elements (including those named "text")
            attrs = build_attributes(self)
            builder.create_and_add_element(name, attributes: attrs) do |el|
              children.each { |child| child.build_xml(el) }
            end
          end

          builder
        end

        def cdata
          super || cdata_children.first&.text
        end

        private

        def node_attributes(node)
          node.attributes.each_with_object({}) do |attr, hash|
            next if attr_is_namespace?(attr)

            ns_prefix = attr.namespace&.prefix
            name = if ns_prefix && !ns_prefix.empty?
                     "#{ns_prefix}:#{attr.name}"
                   else
                     attr.name
                   end

            # W3C: Attributes without prefix are NOT in any namespace
            # (even if parent element has a default namespace)
            namespace_uri = ns_prefix && !ns_prefix.empty? ? attr.namespace&.uri : nil

            hash[name] = XmlAttribute.new(
              name,
              attr.value,
              namespace: namespace_uri,
              namespace_prefix: ns_prefix && !ns_prefix.empty? ? ns_prefix : nil,
            )
          end
        end

        def parse_children(node, default_namespace: nil)
          node.children.filter_map do |child|
            next if child.is_a?(Moxml::ProcessingInstruction)

            self.class.new(child, parent: self,
                                  default_namespace: default_namespace)
          end
        end

        def add_namespaces(node)
          # Ox's node.namespaces returns ALL in-scope namespaces (including inherited).
          # We only add namespaces explicitly declared on THIS element (from native
          # attributes). The XmlElement base class handles inheritance via
          # merge_parent_namespaces for namespace resolution.
          return unless node.native.respond_to?(:attributes) && node.native.attributes

          node.native.attributes.each do |k, v|
            key = k.to_s
            if key == "xmlns"
              add_namespace(NamespaceData.new(v, nil))
            elsif key.start_with?("xmlns:")
              prefix = key.delete_prefix("xmlns:")
              add_namespace(NamespaceData.new(v, prefix))
            end
          end
        end

        def attr_is_namespace?(attr)
          attribute_is_namespace?(attr.name) ||
            namespaces[attr.name]&.uri == attr.value
        end

        def build_attributes(node, _options = {})
          attrs = node.attributes.transform_values(&:value)

          node.own_namespaces.each_value do |namespace|
            uri = namespace.uri
            # Convert FPI to URN per RFC 3151 (Ox requires valid namespace URIs)
            uri = XmlElement.fpi_to_urn(uri) if XmlElement.fpi?(uri)
            attrs[namespace.attr_name] = uri
          end

          attrs
        end
      end
    end
  end
end
