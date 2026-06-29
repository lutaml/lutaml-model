# frozen_string_literal: true

require "moxml"

module Lutaml
  module Xml
    module Builder
      # Base builder for XML construction using moxml.
      # All adapter-specific builders inherit from this class.
      #
      # The builder creates XML documents through moxml's document model.
      # Declaration, doctype, indentation, and line endings are handled
      # by moxml — no manual string assembly.
      class Base
        def self.build(options = {})
          context = Moxml.new(moxml_backend)
          if Lutaml::Model.opal?
            context.config.namespace_validation_mode = :lenient
          end

          encoding_value = options.delete(:encoding)
          context.config.default_indent = options.delete(:indent) if options.key?(:indent)
          context.config.default_line_ending = options.delete(:line_ending) if options.key?(:line_ending)

          doc = context.create_document

          # Capture doctype — added after root to avoid Ox incompatibility
          doctype = options.delete(:doctype)

          instance = new(doc, context, options)
          instance.encoding = encoding_value if encoding_value
          yield(instance) if block_given?

          # Add doctype before root (after build block sets root)
          if doctype && doc.root
            dt = doc.create_doctype(
              doctype[:name],
              doctype[:public_id],
              doctype[:system_id],
            )
            doc.add_child(dt)
          end

          # Handle declaration — configure it on the document so moxml
          # serializes it natively (works across all adapters)
          xml_decl = options.delete(:xml_declaration) || {}
          include_decl = options.delete(:include_declaration)
          force_decl = options.delete(:force_declaration)

          if include_decl
            version = xml_decl[:version] || "1.0"
            encoding = xml_decl[:encoding]
            encoding ||= "UTF-8" unless xml_decl[:had_declaration]
            standalone = xml_decl[:standalone]
            decl = doc.create_declaration(version, encoding, standalone)
            doc.add_child(decl)
            instance.declaration_mode = :default
          elsif force_decl
            decl_encoding = encoding_value || "UTF-8"
            decl = doc.create_declaration("1.0", decl_encoding, nil)
            doc.add_child(decl)
            instance.declaration_mode = :default
          else
            instance.declaration_mode = :none
          end

          instance
        end

        # Override in subclass to set the moxml backend
        def self.moxml_backend
          nil
        end

        attr_reader :doc
        attr_accessor :encoding, :declaration_mode

        def initialize(doc, context, options = {})
          @doc = doc
          @context = context
          @encoding = options[:encoding]
          @current_stack = [doc]
          @declaration_mode = :none
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

          resolve_target(element).add_child(@doc.create_text(text_content.to_s))
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

        def add_processing_instruction(target, content)
          pi = @doc.create_processing_instruction(target.to_s, content.to_s)
          if current_element.is_a?(Moxml::Document)
            root_node = current_element.root
            if root_node
              root_node.add_previous_sibling(pi)
            else
              current_element.add_child(pi)
            end
          else
            current_element.add_child(pi)
          end
          pi
        end

        def text(content)
          add_text(current_element, content)
        end

        def cdata(content)
          add_cdata(current_element, content)
        end

        def to_xml
          return "" unless @doc.root

          result = if @declaration_mode == :none && !has_document_level_nodes?
                     @doc.root.to_xml(declaration: false, expand_empty: false)
                   else
                     @doc.to_xml(declaration: @declaration_mode == :default,
                                 expand_empty: false)
                   end

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

        def has_document_level_nodes?
          @doc.children.any? do |child|
            child != @doc.root &&
              !child.is_a?(Moxml::Text)
          end
        end

        def resolve_target(element)
          element.is_a?(self.class) || element.is_a?(Base) ? element.current_element : element
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
