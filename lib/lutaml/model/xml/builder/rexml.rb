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
            target = element.is_a?(self.class) ? element.current_node : element

            case child
            when String
              # Wrap in a root to support multiple siblings in fragment
              doc = ::REXML::Document.new("<__root__>#{child}</__root__>")
              doc.root&.elements&.each do |node|
                target.add_element(node)
              end
            when ::REXML::Element
              target.add_element(child)
            when self.class
              target.add_element(child.current_node)
            end
          end

          def element(name, attributes = {})
            # Handle multiple mapping names (arrays) by taking the first one
            element_name = name.is_a?(Array) ? name.first.to_s : name.to_s
            rexml_element = ::REXML::Element.new(element_name)
            if block_given?
              element_attributes(rexml_element, attributes)
              @current_node.add_element(rexml_element)
              # Save previous node to reset the pointer for the rest of the iteration
              previous_node = @current_node
              # Set current node to new element as pointer for the block
              @current_node = rexml_element
              yield(self)
              # Reset the pointer for the rest of the iterations
              @current_node = previous_node
            else
              element_attributes(rexml_element, attributes)
              @current_node.add_element(rexml_element)
            end
            rexml_element
          end

          def element_attributes(element, attributes)
            attributes.each do |key, value|
              element.attributes[key.to_s] = value.to_s
            end
          end

          def add_attribute(element, name, value)
            target = element.is_a?(self.class) ? element.current_node : element
            target.attributes[name.to_s] = value.to_s
          end

          # Inserts raw XML content into the element
          def add_xml_fragment(element, content)
            target = element.is_a?(self.class) ? element.current_node : element

            # For raw content, we need to preserve any XML markup while properly
            # escaping special characters. The content might be:
            # 1. Valid XML with properly escaped entities
            # 2. XML-like content with unescaped entities
            # 3. Plain text with special characters

            begin
              # First try: parse as-is (handles properly escaped XML)
              doc = ::REXML::Document.new("<__root__>#{content}</__root__>")
              doc.root&.children&.each do |node|
                target << node
              end
            rescue REXML::ParseException, RuntimeError
              # Second try: escape only ampersands that aren't part of entities
              # This handles content like "R&C" while preserving "A &amp; B"
              escaped_content = content.gsub(/&(?![a-zA-Z]+;|#[0-9]+;|#x[0-9a-fA-F]+;)/, "&amp;")

              begin
                doc = ::REXML::Document.new("<__root__>#{escaped_content}</__root__>")
                doc.root&.children&.each do |node|
                  target << node
                end
              rescue REXML::ParseException, RuntimeError
                # Final fallback: add as escaped text
                target << ::REXML::Text.new(content, false, nil, false)
              end
            end
          end

          def create_and_add_element(
            element_name,
            prefix: (prefix_unset = true
                     nil),
            attributes: {}
          )
            # Handle multiple mapping names (arrays) by taking the first one
            name = element_name.is_a?(Array) ? element_name.first : element_name

            # Only reset namespace if prefix was explicitly set to nil
            @current_namespace = nil if prefix.nil? && !prefix_unset

            prefixed_name = if prefix
                              "#{prefix}:#{name}"
                            elsif @current_namespace && !name.to_s.include?(":")
                              "#{@current_namespace}:#{name}"
                            else
                              name.to_s
                            end

            if block_given?
              element(prefixed_name, attributes) do
                yield(self)
              end
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

          def method_missing(name, *args, &block)
            attributes = args.first.is_a?(Hash) ? args.first : {}
            element(name, attributes, &block)
          end

          def respond_to_missing?(_name, _include_private = false)
            true
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

          def serialize_element(el, indent, force_inline: false)
            return serialize_text_node(el, indent) unless el.is_a?(::REXML::Element)

            name = el.expanded_name
            attrs = el.attributes.map { |k, v| "#{k}=\"#{v}\"" }.join(" ")
            indent_str = @pretty && !force_inline ? "  " * indent : ""

            children = el.children

            # Check if element is empty (no children or only whitespace)
            non_whitespace_children = children.reject { |c| c.is_a?(::REXML::Text) && c.value.empty? }
            if non_whitespace_children.empty?
              # Render as self-closing tag
              if attrs.empty?
                return "#{indent_str}<#{name}/>"
              else
                return "#{indent_str}<#{name} #{attrs}/>"
              end
            end

            # If only one child and it's text/cdata, render inline
            if children.length == 1 && (children.first.is_a?(::REXML::Text) || children.first.is_a?(::REXML::CData))
              text = if children.first.is_a?(::REXML::CData)
                       serialize_text_node(children.first, indent)
                     else
                       serialize_text_content(children.first)
                     end
              if attrs.empty?
                return "#{indent_str}<#{name}>#{text}</#{name}>"
              else
                return "#{indent_str}<#{name} #{attrs}>#{text}</#{name}>"
              end
            end

            if @pretty && !force_inline
              # Check if we have mixed content (text nodes mixed with elements)
              has_text_nodes = children.any? { |c| c.is_a?(::REXML::Text) && !c.value.strip.empty? }
              has_element_nodes = children.any? { |c| c.is_a?(::REXML::Element) }
              is_mixed_content = has_text_nodes && has_element_nodes

              if is_mixed_content
                # For mixed content, render inline without extra whitespace
                # Children are serialized without indentation to preserve compact format
                open_tag = attrs.empty? ? "#{indent_str}<#{name}>" : "#{indent_str}<#{name} #{attrs}>"
                inner = children.map { |c| serialize_element(c, 0, force_inline: true) }.join("")

                # If the content starts with a newline (pretty-printed), add a newline before closing tag
                first_child_starts_with_newline = children.first.is_a?(::REXML::Text) &&
                  children.first.value.start_with?("\n")
                close_tag = first_child_starts_with_newline ? "\n</#{name}>" : "</#{name}>"
                (open_tag + inner + close_tag)
              else
                # Pretty print with full indentation
                open_tag = attrs.empty? ? "#{indent_str}<#{name}>\n" : "#{indent_str}<#{name} #{attrs}>\n"
                inner = children.map { |c| serialize_element(c, indent + 1) }.join("\n")
                close_tag = "\n#{indent_str}</#{name}>"
                (open_tag + inner + close_tag)
              end
            else
              # Compact output
              open_tag = attrs.empty? ? "<#{name}>" : "<#{name} #{attrs}>"
              inner = children.map { |c| serialize_element(c, 0, force_inline: true) }.join("")
              close_tag = "</#{name}>"
              (open_tag + inner + close_tag)
            end
          end

          def serialize_text_node(node, _indent)
            case node
            when ::REXML::CData
              "<![CDATA[#{node.value}]]>"
            when ::REXML::Text
              serialize_text_content(node)
            when ::REXML::Comment
              "<!--#{node.string}-->"
            else
              # Fallback for unexpected node types
              node.to_s
            end
          end

          def serialize_text_content(text_node)
            # Use to_s to properly escape special characters
            text_node.to_s
          end
        end
      end
    end
  end
end
