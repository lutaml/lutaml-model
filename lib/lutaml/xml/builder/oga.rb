# frozen_string_literal: true

require "moxml"

module Lutaml
  module Xml
    module Builder
      # Moxml DOM-based builder for XML construction (Oga backend).
      class Oga
        def self.build(options = {})
          context = Moxml.new(:oga)
          doc = context.create_document
          instance = new(doc, context, options)
          yield(instance) if block_given?
          instance
        end

        attr_reader :doc, :encoding

        def initialize(doc_or_options = {}, context = nil, options = {})
          if doc_or_options.is_a?(Hash)
            options = doc_or_options
            context = Moxml.new(:oga)
            @doc = context.create_document
          else
            @doc = doc_or_options
          end
          @context = context
          @encoding = options[:encoding]
          @current_stack = [@doc]

          yield(self) if block_given?
        end

        def current_element
          @current_stack.last
        end
        alias current_node current_element

        def xml
          self
        end

        def parent
          current_element
        end

        def create_and_add_element(
          element_name,
          prefix: (prefix_unset = true
                   nil),
          attributes: {},
          blank_xmlns: false
        )
          element_name = element_name.first if element_name.is_a?(Array)

          new_el = @doc.create_element(element_name)
          apply_attributes(new_el, attributes, blank_xmlns)
          resolve_namespace(new_el, prefix, prefix_unset)
          attach_to_parent(new_el, prefix, prefix_unset)
          with_element_context(new_el) { yield(self) } if block_given?

          new_el
        end

        def add_xml_fragment(element, content)
          target = resolve_target(element)
          parsed = @context.parse("<__root__>#{content}</__root__>")
          parsed.root&.children&.each { |child| target.add_child(child) }
        rescue Moxml::ParseError
          target.add_child(@doc.create_text(content.to_s))
        end

        def add_text(element, text_content, cdata: false)
          return add_cdata(element, text_content) if cdata

          target = resolve_target(element)
          target.add_child(@doc.create_text(text_content.to_s))
        end

        def add_cdata(element, value)
          resolve_target(element).add_child(@doc.create_cdata(value.to_s))
        end

        def add_comment(element_or_text, text = nil)
          if text.nil?
            target = current_element
            comment_text = element_or_text
          else
            target = resolve_target(element_or_text)
            comment_text = text
          end
          target.add_child(@doc.create_comment(comment_text.to_s))
        end

        def text(content)
          add_text(current_element, content)
        end

        def cdata(content)
          add_cdata(current_element, content)
        end

        def to_s
          return "" unless @doc.root

          @doc.root.to_xml(declaration: false, expand_empty: false)
        end

        def to_xml
          result = to_s
          result = result.encode(encoding) if encoding && result.encoding.to_s != encoding
          result
        end

        def method_missing(method_name, *args, &)
          attrs = args.first.is_a?(Hash) ? args.first : {}
          create_and_add_element(method_name.to_s, attributes: attrs, &)
        end

        def respond_to_missing?(_method_name, _include_private = false)
          true
        end

        private

        def resolve_target(element)
          element.is_a?(self.class) ? element.current_element : element
        end

        def apply_attributes(new_el, attributes, blank_xmlns)
          attributes = attributes&.dup || {}
          attributes["xmlns"] = "" if blank_xmlns

          attributes.each do |key, value|
            k = key.to_s
            if k.start_with?("xmlns:")
              new_el.add_namespace(k.sub("xmlns:", ""), value.to_s)
            elsif k == "xmlns"
              new_el.add_namespace(nil, value.to_s)
            else
              new_el[k] = value.to_s
            end
          end
        end

        def resolve_namespace(new_el, prefix, prefix_unset)
          if !prefix_unset && prefix
            ns = new_el.in_scope_namespaces.find { |n| n.prefix == prefix }
            new_el.namespace = ns if ns
          elsif !prefix_unset && prefix.nil?
            new_el.namespace = nil
          else
            default_ns = new_el.in_scope_namespaces.find { |n| n.prefix.nil? }
            new_el.namespace = default_ns if default_ns
          end
        end

        def attach_to_parent(new_el, prefix, prefix_unset)
          if current_element.is_a?(Moxml::Document)
            current_element.root = new_el
          else
            current_element.add_child(new_el)

            if new_el.namespace.nil? && !prefix_unset && prefix
              ns = new_el.in_scope_namespaces.find { |n| n.prefix == prefix }
              new_el.namespace = ns if ns
            end
          end
        end

        def with_element_context(new_el)
          @current_stack.push(new_el)
          begin
            yield
          ensure
            @current_stack.pop
          end
        end
      end
    end
  end
end
