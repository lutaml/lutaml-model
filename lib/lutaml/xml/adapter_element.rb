# frozen_string_literal: true

module Lutaml
  module Xml
    # Base element wrapper for moxml-backed XML adapters.
    # NokogiriElement, Ox::Element, Oga::Element, Rexml::Element
    # all inherit from this class.
    class AdapterElement < XmlElement
      NamespaceData = Lutaml::Xml::Adapter::NamespaceData

      def initialize(node, parent: nil, default_namespace: nil)
        @moxml_node = node

        node_type = case node
                    when Moxml::Cdata then :cdata
                    when Moxml::Text then :text
                    when Moxml::Comment then :comment
                    when Moxml::ProcessingInstruction then :processing_instruction
                    else :element
                    end

        text = case node
               when Moxml::Element
                 namespace_name = node.namespace&.prefix
                 # moxml >= 0.5.33 contract: #namespaces is the full
                 # in-scope map (parity with Nokogiri, #198/#201); the
                 # own-declarations shape this parse path needs is
                 # #namespace_definitions.
                 ns_defs = node.namespace_definitions

                 has_empty_xmlns = ns_defs.any? do |ns|
                   ns.prefix.nil? && ns.uri == ""
                 end

                 explicit_no_namespace = XmlElement.detect_explicit_no_namespace(
                   has_empty_xmlns: has_empty_xmlns,
                   node_namespace_nil: node.namespace.nil? || node.namespace&.uri == "",
                 )

                 add_namespaces_from_defs(ns_defs, is_root: parent.nil?)

                 if parent.nil? && !namespace_name && node.namespace&.uri &&
                     node.namespace.uri != ""
                   default_namespace = node.namespace.uri
                 end

                 children = parse_children(node,
                                           default_namespace: default_namespace)
                 attributes, attr_order = node_attributes_with_order(node)
                 @root = node
                 EncodingNormalizer.normalize_to_utf8(node.inner_text)
               when Moxml::Text
                 EncodingNormalizer.normalize_to_utf8(node.content)
               when Moxml::Cdata
                 EncodingNormalizer.normalize_to_utf8(node.content)
               when Moxml::Comment
                 EncodingNormalizer.normalize_to_utf8(node.content)
               when Moxml::ProcessingInstruction
                 EncodingNormalizer.normalize_to_utf8(
                   node.content.to_s.sub(/\A\s+/, ""),
                 )
               end

        name = adapter_class.name_of(node)
        super(
          node,
          attributes || NO_ATTRIBUTES,
          children || NO_CHILDREN,
          text,
          name: name,
          parent_document: parent,
          namespace_prefix: namespace_name,
          default_namespace: default_namespace,
          explicit_no_namespace: explicit_no_namespace || false,
          node_type: node_type,
          attribute_order: attr_order
        )
      end

      def text?
        %i[text cdata].include?(@node_type)
      end

      def text
        super || @text
      end

      def to_xml(_builder = nil)
        @moxml_node.to_xml(declaration: false, expand_empty: false)
      end

      def build_xml(builder = nil)
        if cdata?
          builder.add_text(builder.current_node, @text.to_s, cdata: true)
        elsif comment?
          builder.add_comment(builder.current_node, @text.to_s)
        elsif processing_instruction?
          builder.add_processing_instruction(name, @text.to_s)
        elsif text? && !element?
          builder.add_text(builder.current_node, build_text_for_xml.to_s)
        else
          build_element_xml(builder)
        end

        builder
      end

      def inner_xml
        children.map(&:to_xml).join
      end

      private

      def build_element_xml(builder)
        builder.create_and_add_element(name,
                                       attributes: build_attributes(self)) do |xml|
          children.each { |child| child.build_xml(xml) }
        end
      end

      def build_text_for_xml
        @text
      end

      def adapter_class
        raise NotImplementedError, "#{self.class} must implement #adapter_class"
      end

      def node_attributes(node)
        return {} unless node.is_a?(Moxml::Element)

        node.attributes.each_with_object({}) do |attr, hash|
          next if attr_is_namespace?(attr)

          ns_prefix = attr.namespace&.prefix
          ns_prefix = nil if ns_prefix && ns_prefix.empty?

          attr_name = ns_prefix ? "#{ns_prefix}:#{attr.name}" : attr.name

          hash[attr_name] = XmlAttribute.new(
            attr_name,
            attribute_value_for_build(attr),
            namespace: ns_prefix ? attr.namespace&.uri : nil,
            namespace_prefix: ns_prefix,
          )
        end
      end

      # Shared frozen empties: the parse path hands these straight into
      # XmlElement (which never mutates the containers it is given), so
      # attribute-less elements — the majority in real documents — build
      # nothing here.
      NO_ATTRIBUTES = {}.freeze # rubocop:todo Lint/UselessConstantScoping
      NO_CHILDREN = [].freeze # rubocop:todo Lint/UselessConstantScoping
      EMPTY_ATTRIBUTES = [{}, nil].freeze # rubocop:todo Lint/UselessConstantScoping

      def node_attributes_with_order(node)
        return EMPTY_ATTRIBUTES unless node.is_a?(Moxml::Element)

        attrs = node.attributes
        return EMPTY_ATTRIBUTES if attrs.respond_to?(:empty?) && attrs.empty?

        order = []
        hash = node.attributes.each_with_object({}) do |attr, h|
          next if attr_is_namespace?(attr)

          ns_prefix = attr.namespace&.prefix
          ns_prefix = nil if ns_prefix && ns_prefix.empty?

          attr_name = ns_prefix ? "#{ns_prefix}:#{attr.name}" : attr.name
          order << attr_name

          h[attr_name] = XmlAttribute.new(
            attr_name,
            attribute_value_for_build(attr),
            namespace: ns_prefix ? attr.namespace&.uri : nil,
            namespace_prefix: ns_prefix,
          )
        end
        [hash, order.empty? ? nil : order]
      end

      def attribute_value_for_build(attr)
        attr.value
      end

      def parse_children(node, default_namespace: nil)
        return NO_CHILDREN unless node.children

        # Non-element children (text/cdata/comment/PI) stay RAW moxml
        # nodes in the list — the hot scalar parse path reads text off
        # the element (inner_text) and never touches their wrappers, so
        # wrapping every text node eagerly paid half the parse tree for
        # nothing. #children wraps them on first access; document order
        # is preserved because they sit at their original positions.
        node.children.filter_map do |child|
          next if (child.is_a?(Moxml::Text) || child.is_a?(Moxml::Cdata)) && child.content.empty?

          if child.is_a?(Moxml::Element)
            self.class.new(child, parent: self,
                                  default_namespace: default_namespace)
          else
            child
          end
        end
      end

      public

      def children
        return @children if @children.empty?

        unless @non_element_children_wrapped
          @children.map! do |child|
            if child.is_a?(Moxml::Node) && !child.is_a?(Moxml::Element)
              self.class.new(child, parent: self)
            else
              child
            end
          end
          @non_element_children_wrapped = true
        end
        @children
      end

      def children=(new_children)
        @non_element_children_wrapped = true
        super
      end

      def element_children
        return @element_children if defined?(@element_children)

        @element_children = @children.reject do |child|
          raw_non_element_child?(child) ||
            (child.is_a?(XmlElement) &&
              (child.text? || child.processing_instruction?))
        end
      end

      def raw_non_element_child?(child)
        child.is_a?(Moxml::Node) && !child.is_a?(Moxml::Element)
      end

      # Order consumes raw non-element children inline: wrapping them
      # just to read .text/.content would materialize the whole lazy
      # layer on every parse.
      def order
        return @order_cache if @order_cache

        @order_cache = @children.filter_map do |child|
          case child
          when Moxml::Cdata
            Lutaml::Xml::Element.new("Text", "#cdata-section",
                                     text_content: child.content,
                                     node_type: :cdata)
          when Moxml::Text
            next if child.content.nil?

            Lutaml::Xml::Element.new("Text", "text",
                                     text_content: child.content,
                                     node_type: :text)
          when Moxml::Comment
            Lutaml::Xml::Element.new("Comment", "comment",
                                     text_content: child.content,
                                     node_type: :comment)
          when Moxml::ProcessingInstruction
            Lutaml::Xml::Element.new("ProcessingInstruction",
                                     child.target,
                                     text_content: child.content.to_s.sub(/\A\s+/, ""),
                                     node_type: :processing_instruction)
          else
            next if child.is_a?(Moxml::Node)

            if child.cdata?
              Lutaml::Xml::Element.new("Text", "#cdata-section",
                                       text_content: child.text,
                                       node_type: :cdata)
            elsif child.text?
              next if child.text.nil?

              Lutaml::Xml::Element.new("Text", "text",
                                       text_content: child.text,
                                       node_type: :text)
            elsif child.comment?
              Lutaml::Xml::Element.new("Comment", "comment",
                                       text_content: child.text,
                                       node_type: :comment)
            elsif child.processing_instruction?
              Lutaml::Xml::Element.new("ProcessingInstruction",
                                       child.unprefixed_name,
                                       text_content: child.text,
                                       node_type: :processing_instruction)
            else
              Lutaml::Xml::Element.new("Element", child.unprefixed_name,
                                       node_type: :element,
                                       namespace_uri: child.namespace_uri,
                                       namespace_prefix: child.namespace_prefix)
            end
          end
        end.each(&:freeze).freeze
      end

      def add_namespaces_from_defs(ns_defs, is_root: false)
        has_default_xmlns = is_root || ns_defs.any? { |ns| ns.prefix.nil? }

        ns_defs.each do |namespace|
          ns = NamespaceData.new(namespace.uri, namespace.prefix)
          add_namespace(ns) if ns.prefix || has_default_xmlns
        end
      end

      def attr_is_namespace?(attr)
        attribute_is_namespace?(attr.name) ||
          namespaces[attr.name]&.uri == attr.value
      end

      def build_attributes(node, _options = {})
        attrs = node.attributes.transform_values(&:value)
        attrs.merge(build_namespace_attributes(node))
      end

      def build_namespace_attributes(node)
        namespace_attrs = {}

        node.own_namespaces.each_value do |namespace|
          uri = namespace.uri
          uri = XmlElement.fpi_to_urn(uri) if XmlElement.fpi?(uri)
          namespace_attrs[namespace.attr_name] = uri
        end

        namespace_attrs
      end
    end
  end
end
