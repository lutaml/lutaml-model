require "ox"
require_relative "document"
require_relative "builder/ox"

module Lutaml
  module Model
    module Xml
      class OxAdapter < Document
        def self.parse(xml, options = {})
          Ox.default_options = Ox.default_options.merge(encoding: encoding(xml, options))

          parsed = Ox.parse(xml)
          # Ox.parse returns Ox::Document if XML has declaration, Ox::Element otherwise
          root_element = parsed.is_a?(::Ox::Document) ? parsed.nodes.first : parsed
          @root = OxElement.new(root_element)
          new(@root, Ox.default_options[:encoding])
        end

        def to_xml(options = {})
          builder_options = { version: options[:version] }

          builder_options[:encoding] = if options.key?(:encoding)
                                         options[:encoding] unless options[:encoding].nil?
                                       elsif options.key?(:parse_encoding)
                                         options[:parse_encoding]
                                       else
                                         "UTF-8"
                                       end

          builder = Builder::Ox.build(builder_options)
          builder.xml.instruct(:xml, encoding: builder_options[:encoding])

          if @root.is_a?(Lutaml::Model::Xml::OxElement)
            @root.build_xml(builder)
          elsif ordered?(@root, options)
            build_ordered_element(builder, @root, options)
          else
            mapper_class = options[:mapper_class] || @root.class
            options[:xml_attributes] = build_namespace_attributes(mapper_class)
            build_element(builder, @root, options)
          end

          xml_data = builder.xml.to_s
          stripped_data = xml_data.lines.drop(1).join
          options[:declaration] ? declaration(options) + stripped_data : stripped_data
        end

        private

        def build_ordered_element(builder, element, options = {})
          mapper_class = determine_mapper_class(element, options)
          xml_mapping = mapper_class.mappings_for(:xml)
          return builder unless xml_mapping

          attributes = build_attributes(element, xml_mapping, options).compact

          prefix = determine_namespace_prefix(options, xml_mapping)
          prefixed_xml = builder.add_namespace_prefix(prefix)

          tag_name = options[:tag_name] || xml_mapping.root_element
          prefixed_xml.create_and_add_element(tag_name, prefix: prefix, attributes: attributes) do |el|
            if options.key?(:namespace_prefix) && !options[:namespace_prefix]
              prefixed_xml.add_namespace_prefix(nil)
            end

            index_hash = {}
            content = []

            element.element_order.each do |object|
              object_key = "#{object.name}-#{object.type}"
              index_hash[object_key] ||= -1
              curr_index = index_hash[object_key] += 1

              element_rule = xml_mapping.find_by_name(object.name, type: object.type)
              next if element_rule.nil? || options[:except]&.include?(element_rule.to)

              attribute_def = attribute_definition_for(element, element_rule,
                                                       mapper_class: mapper_class)
              value = attribute_value_for(element, element_rule)

              next if element_rule == xml_mapping.content_mapping && element_rule.cdata && object.text?

              if element_rule == xml_mapping.content_mapping
                text = element.send(xml_mapping.content_mapping.to)
                text = text[curr_index] if text.is_a?(Array)

                next el.add_text(el, text, cdata: element_rule.cdata) if element.mixed?

                content << text
              elsif !value.nil? || element_rule.render_nil?
                value = value[curr_index] if attribute_def.collection?

                add_to_xml(
                  el,
                  element,
                  nil,
                  value,
                  options.merge(
                    attribute: attribute_def,
                    rule: element_rule,
                  ),
                )
              end
            end

            el.add_text(el, content.join)
          end
        end
      end

      class OxElement < XmlElement
        def initialize(node, root_node: nil, inherited_default_namespace: nil)
          case node
          when String
            super("text", {}, [], node, parent_document: root_node, name: "text")
          when Ox::Comment
            super("comment", {}, [], node.value, parent_document: root_node, name: "comment")
          when Ox::CData
            super("#cdata-section", {}, [], node.value, parent_document: root_node, name: "#cdata-section")
          else
            # Extract default namespace (xmlns without prefix)
            default_namespace = nil
            namespace_attributes(node.attributes).each do |(name, value)|
              if root_node
                root_node.add_namespace(XmlNamespace.new(value, name))
              else
                add_namespace(XmlNamespace.new(value, name))
              end

              # Capture default namespace
              if name.to_s == "xmlns"
                default_namespace = value
              end
            end

            # Inherit default namespace from parent if not explicitly set
            default_namespace ||= inherited_default_namespace

            attributes = node.attributes.each_with_object({}) do |(name, value), hash|
              next if attribute_is_namespace?(name)

              namespace_prefix = name.to_s.split(":").first
              if (n = name.to_s.split(":")).length > 1
                namespace = (root_node || self).namespaces[namespace_prefix]&.uri
                namespace ||= XML_NAMESPACE_URI
                prefix = n.first
              end

              hash[name.to_s] = XmlAttribute.new(
                name.to_s,
                value,
                namespace: namespace,
                namespace_prefix: prefix,
              )
            end

            prefix, name = separate_name_and_prefix(node)

            # We need to call super first to set @default_namespace, then parse children
            # But we can't because super needs the children. So we pass default_namespace explicitly.
            super(
              node,
              attributes,
              [], # Will set children after super
              node.text,
              parent_document: root_node,
              name: name,
              namespace_prefix: prefix,
              default_namespace: default_namespace,
            )

            # Now parse children with proper default_namespace context
            @children = parse_children(node, root_node: root_node || self,
                                      default_namespace: default_namespace)
          end
        end

        def separate_name_and_prefix(node)
          name = node.name.to_s

          return [nil, name] unless name.include?(":")

          prefix, _, name = name.partition(":")
          [prefix, name]
        end

        def to_xml
          return text if text?

          build_xml.xml.to_s
        end

        def inner_xml
          # Ox builder by default, adds a newline at the end, so `chomp` is used
          children.map { |child| child.to_xml.chomp }.join
        end

        def build_xml(builder = nil)
          builder ||= Builder::Ox.build
          attrs = build_attributes(self)

          if text?
            builder.add_text(builder, text)
          else
            builder.create_and_add_element(name, attributes: attrs) do |el|
              children.each { |child| child.build_xml(el) }
            end
          end

          builder
        end

        def namespace_attributes(attributes)
          attributes.select { |attr| attribute_is_namespace?(attr) }
        end

        def text?
          # false
          children.empty? && text&.length&.positive?
        end

        def build_attributes(node)
          attrs = node.attributes.transform_values(&:value)

          node.own_namespaces.each_value do |namespace|
            attrs[namespace.attr_name] = namespace.uri
          end

          attrs
        end

        def nodes
          children
        end

        def cdata
          super || cdata_children.first&.text
        end

        def text
          super || cdata
        end

        private

        def parse_children(node, root_node: nil, default_namespace: nil)
          node.nodes.map do |child|
            OxElement.new(child, root_node: root_node,
                         inherited_default_namespace: default_namespace)
          end
        end
      end
    end
  end
end
