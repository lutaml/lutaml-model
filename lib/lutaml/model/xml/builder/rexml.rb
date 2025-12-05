# frozen_string_literal: true

require "rexml/document"

module Lutaml
  module Model
    module Xml
      module Builder
        class Rexml
          def self.build(options = {}, &block)
            new(options, &block)
          end

          attr_reader :doc, :current_node, :encoding

          def initialize(options = {})
            @doc = ::REXML::Document.new
            @current_node = @doc
            @encoding = options[:encoding]
            @pretty = options.fetch(:pretty, true) # Default to pretty formatting
            @current_namespace = nil # Track current namespace prefix

            # Only add XML declaration if explicitly requested by caller
            if options[:declaration]
              declaration = ::REXML::XMLDecl.new(
                options[:version] || "1.0",
                options[:encoding],
                options[:standalone],
              )
              @doc << declaration
            end

            yield(self) if block_given?
          end

          def create_element(name, attributes = {})
            element = ::REXML::Element.new(name.to_s)
            attributes.each { |key, value| element.attributes[key.to_s] = value.to_s }
            element
          end

          def add_element(element, child)
            target = resolve_target_element(element)
            add_child_to_element(target, child)
          end

          def element(name, attributes = {})
            # Handle multiple mapping names (arrays) by taking the first one
            element_name = name.is_a?(Array) ? name.first.to_s : name.to_s
            rexml_element = ::REXML::Element.new(element_name)
            attributes.each do |key, value|
              rexml_element.attributes[key.to_s] = value.to_s
            end
            @current_node.add_element(rexml_element)
            if block_given?
              # Save previous node to reset the pointer for the rest of the iteration
              previous_node = @current_node
              # Set current node to new element as pointer for the block
              @current_node = rexml_element
              yield(self)
              # Reset the pointer for the rest of the iterations
              @current_node = previous_node
            end
            rexml_element
          end

          def add_attribute(element, name, value)
            target = element.is_a?(self.class) ? element.current_node : element
            target.attributes[name.to_s] = value.to_s
          end

          # Inserts raw XML content into the element
          def add_xml_fragment(element, content)
            target = resolve_target_element(element)

            parse_and_add_fragment(target, content)
          end

          def create_and_add_element(
            element_name,
            prefix: (prefix_unset = true
                     nil),
            attributes: {}
          )
            name = element_name.is_a?(Array) ? element_name.first : element_name
            @current_namespace = nil if prefix.nil? && !prefix_unset
            prefixed_name = build_prefixed_name(name, prefix)

            if block_given?
              element(prefixed_name, attributes) { yield(self) }
            else
              element(prefixed_name, attributes)
            end
          end

          def add_text(element, text, cdata: false)
            target = element.is_a?(self.class) ? element.current_node : element
            text_str = text.to_s

            # REXML requires UTF-8, so convert if needed
            if text_str.encoding.to_s != "UTF-8"
              text_str = text_str.encode("UTF-8")
            end

            text_node = if cdata
                          ::REXML::CData.new(text_str)
                        else
                          ::REXML::Text.new(text_str, true)
                        end
            target << text_node
          end

          def add_namespace_prefix(prefix)
            @current_namespace = prefix
            self
          end

          def parent
            @current_node
          end

          def to_s
            serialize_document(@doc)
          end

          def to_xml
            result = to_s
            # Convert to target encoding if specified
            if @encoding && result.encoding.to_s != @encoding
              result = result.encode(@encoding)
            end
            result
          end

          private

          # Helper methods for add_element
          def resolve_target_element(element)
            element.is_a?(self.class) ? element.current_node : element
          end

          def add_child_to_element(target, child)
            case child
            when String
              add_string_fragment(target, child)
            when ::REXML::Element
              target.add_element(child)
            when self.class
              target.add_element(child.current_node)
            end
          end

          def add_string_fragment(target, fragment)
            doc = ::REXML::Document.new("<__root__>#{fragment}</__root__>")
            doc.root&.elements&.each { |node| target.add_element(node) }
          end

          # Helper methods for add_xml_fragment
          def parse_and_add_fragment(target, content)
            parse_fragment_as_is(target, content)
          rescue REXML::ParseException, RuntimeError
            parse_fragment_with_escaping(target, content)
          end

          def parse_fragment_as_is(target, content)
            doc = ::REXML::Document.new("<__root__>#{content}</__root__>")
            doc.root&.children&.each { |node| target << node }
          end

          def parse_fragment_with_escaping(target, content)
            escaped_content = content.gsub(/&(?![a-zA-Z]+;|#[0-9]+;|#x[0-9a-fA-F]+;)/, "&amp;")
            parse_fragment_as_is(target, escaped_content)
          rescue REXML::ParseException, RuntimeError
            target << ::REXML::Text.new(content, false, nil, false)
          end

          def build_prefixed_name(name, prefix)
            return "#{prefix}:#{name}" if prefix
            return "#{@current_namespace}:#{name}" if @current_namespace && !name.to_s.include?(":")

            name.to_s
          end

          # Helper methods for serialize_element
          def serialize_attributes(attributes)
            attributes.map { |key, val| "#{key}=\"#{val}\"" }.join(" ")
          end

          def empty_element?(children)
            children.reject { |child| child.is_a?(::REXML::Text) && child.value.empty? }.empty?
          end

          def single_text_child?(children)
            children.length == 1 && (children.first.is_a?(::REXML::Text) || children.first.is_a?(::REXML::CData))
          end

          def render_empty_element(name, attrs, indent_str)
            return "#{indent_str}<#{name}/>" if attrs.empty?

            "#{indent_str}<#{name} #{attrs}/>"
          end

          def render_single_text_element(name, attrs, indent_str, children, indent)
            child = children.first
            text = child.is_a?(::REXML::CData) ? serialize_text_node(child, indent) : child.to_s
            return "#{indent_str}<#{name}>#{text}</#{name}>" if attrs.empty?

            "#{indent_str}<#{name} #{attrs}>#{text}</#{name}>"
          end

          def render_element_with_children(name, attrs, indent_str, children, indent, force_inline)
            if @pretty && !force_inline
              render_pretty_element(name, attrs, indent_str, children, indent)
            else
              render_compact_element(name, attrs, children)
            end
          end

          def render_pretty_element(name, attrs, indent_str, children, indent)
            if mixed_content?(children)
              render_mixed_content_element(name, attrs, indent_str, children)
            else
              render_indented_element(name, attrs, indent_str, children, indent)
            end
          end

          def mixed_content?(children)
            has_text = children.any? { |child| child.is_a?(::REXML::Text) && !child.value.strip.empty? }
            has_elements = children.any?(::REXML::Element)
            has_text && has_elements
          end

          def render_mixed_content_element(name, attrs, indent_str, children)
            open_tag = build_open_tag(name, attrs, indent_str, false)
            inner = children.map { |child| serialize_element(child, 0, force_inline: true) }.join
            close_tag = mixed_content_close_tag(children, name)
            open_tag + inner + close_tag
          end

          def mixed_content_close_tag(children, name)
            starts_with_newline = children.first.is_a?(::REXML::Text) && children.first.value.start_with?("\n")
            starts_with_newline ? "\n</#{name}>" : "</#{name}>"
          end

          def render_indented_element(name, attrs, indent_str, children, indent)
            open_tag = build_open_tag(name, attrs, indent_str, true)
            inner = children.map { |child| serialize_element(child, indent + 1) }.join("\n")
            close_tag = "\n#{indent_str}</#{name}>"
            open_tag + inner + close_tag
          end

          def render_compact_element(name, attrs, children)
            open_tag = build_open_tag(name, attrs, "", false)
            inner = children.map { |child| serialize_element(child, 0, force_inline: true) }.join
            close_tag = "</#{name}>"
            open_tag + inner + close_tag
          end

          def build_open_tag(name, attrs, indent_str, with_newline)
            tag = attrs.empty? ? "#{indent_str}<#{name}>" : "#{indent_str}<#{name} #{attrs}>"
            with_newline ? "#{tag}\n" : tag
          end

          def serialize_document(doc)
            parts = []
            # If XML declaration present in doc, include it
            if doc.children.first.is_a?(::REXML::XMLDecl)
              decl = doc.children.first
              enc_part = decl.encoding ? " encoding=\"#{decl.encoding}\"" : ""
              parts << "<?xml version=\"#{decl.version}\"#{enc_part}?>\n"
            end
            root = doc.root
            parts << serialize_element(root, 0)
            parts.join
          end

          def serialize_element(element, indent, force_inline: false)
            return serialize_text_node(element, indent) unless element.is_a?(::REXML::Element)

            name = element.expanded_name
            attrs = serialize_attributes(element.attributes)
            indent_str = @pretty && !force_inline ? "  " * indent : ""
            children = element.children

            return render_empty_element(name, attrs, indent_str) if empty_element?(children)
            return render_single_text_element(name, attrs, indent_str, children, indent) if single_text_child?(children)

            render_element_with_children(name, attrs, indent_str, children, indent, force_inline)
          end

          def serialize_text_node(node, _indent)
            case node
            when ::REXML::CData
              "<![CDATA[#{node.value}]]>"
            when ::REXML::Comment
              "<!--#{node.string}-->"
            else
              # Fallback for unexpected node types
              node.to_s
            end
          end
        end
      end
    end
  end
end
