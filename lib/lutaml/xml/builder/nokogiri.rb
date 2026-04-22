require "moxml"
require "nokogiri"

module Lutaml
  module Xml
    module Builder
      # Moxml DOM-based builder for XML construction.
      #
      # Uses Moxml APIs for all DOM operations including element creation,
      # text/CDATA nodes, namespace handling, and serialization.
      #
      # Note: We still use ::Nokogiri::XML::Builder.new.doc as the initial
      # document because Builder documents have special namespace inheritance
      # behavior (add_child propagates parent namespace to children without
      # explicit namespace). Plain Nokogiri::XML::Document.new does NOT have
      # this behavior.
      class Nokogiri
        def self.build(options = {})
          context = Moxml.new

          # Use Nokogiri::XML::Builder's document as the native doc.
          # Builder documents have special namespace inheritance behavior:
          # add_child propagates parent namespace to children without explicit namespace.
          # Plain Nokogiri::XML::Document.new does NOT have this behavior.
          native_doc = ::Nokogiri::XML::Builder.new.doc
          if options[:encoding]
            native_doc.encoding = options[:encoding]
          end
          doc = Moxml::Document.new(native_doc, context)

          instance = new(doc, context)

          if block_given?
            yield(instance)
          end

          instance
        end

        attr_reader :doc

        def initialize(doc, context)
          @doc = doc
          @context = context
          @current_stack = [doc]
        end

        # Returns the current parent element (top of stack).
        # Used by NokogiriElement#build_xml for text/cdata nodes.
        def current_element
          @current_stack.last
        end

        # Compatibility alias — NokogiriElement calls builder.xml.parent
        # to get the current element. This shim provides that interface.
        def xml
          self
        end

        # Alias for current_element, used by NokogiriElement via builder.xml.parent
        def parent
          current_element
        end

        def create_element(name, attributes = {})
          el = @doc.create_element(name)
          attributes.each do |k, v|
            el[k.to_s] = v.to_s
          end
          el
        end

        def add_element(parent_el, child)
          parent_el.add_child(child)
        end

        def add_attribute(element, name, value)
          element[name.to_s] = value.to_s
        end

        def create_and_add_element(
          element_name,
          prefix: (prefix_unset = true
                   nil),
          attributes: {},
          blank_xmlns: false
        )
          element_name = element_name.first if element_name.is_a?(Array)

          el = @doc.create_element(element_name)

          # W3C Compliance: Add xmlns="" if needed to prevent default namespace inheritance
          attributes = attributes&.dup || {}
          attributes["xmlns"] = "" if blank_xmlns

          attributes.each do |k, v|
            key = k.to_s
            if key.start_with?("xmlns:")
              ns_prefix = key.sub("xmlns:", "")
              el.add_namespace(ns_prefix, v.to_s)
            elsif key == "xmlns"
              el.add_namespace(nil, v.to_s)
            else
              el[key] = v.to_s
            end
          end

          # Resolve element's namespace from its prefix if applicable
          if !prefix_unset && prefix
            # Prefixed element: find matching namespace from element's own scopes
            ns = el.in_scope_namespaces.find { |n| n.prefix == prefix }
            el.namespace = ns if ns
          elsif !prefix_unset && prefix.nil?
            # Explicitly no prefix (prefix: nil) — blank namespace
            el.namespace = nil
          else
            # For unprefixed elements, check if there's a default namespace
            default_ns = el.in_scope_namespaces.find { |n| n.prefix.nil? }
            el.namespace = default_ns if default_ns
          end

          # Add to parent
          if current_element.is_a?(Moxml::Document)
            current_element.root = el
          else
            current_element.add_child(el)

            # After adding to parent, resolve namespace from parent's scopes
            # (Nokogiri builder docs automatically propagate parent namespace to children)
            # For explicitly prefixed elements not yet resolved, try parent's scopes
            if !prefix_unset && prefix && el.namespace.nil?
              ns = el.in_scope_namespaces.find { |n| n.prefix == prefix }
              el.namespace = ns if ns
            end
          end

          if block_given?
            @current_stack.push(el)
            begin
              yield(self)
            ensure
              @current_stack.pop
            end
          end

          el
        end

        def add_xml_fragment(element, content)
          target = if element.is_a?(self.class)
                     element.current_element
                   else
                     element
                   end

          # Parse fragment and add children to target (preserving existing children)
          parsed = @context.parse("<__root__>#{content}</__root__>")
          parsed.root&.children&.each do |child_node|
            target.add_child(child_node)
          end
        end

        def add_text(element, text, cdata: false)
          return add_cdata(element, text) if cdata

          target = if element.is_a?(self.class)
                     element.current_element
                   else
                     element
                   end

          text_node = @doc.create_text(text.to_s)
          target.add_child(text_node)
        end

        def add_cdata(element, value)
          target = if element.is_a?(self.class)
                     element.current_element
                   else
                     element
                   end

          cdata_node = @doc.create_cdata(value.to_s)
          target.add_child(cdata_node)
        end

        def add_namespace_prefix(_prefix)
          # With Moxml, namespace prefixes are registered via add_namespace on elements.
          # This is a no-op in the new builder; namespaces are declared via attributes.
          self
        end

        def method_missing(method_name, *args, &)
          # Fallback for any direct element creation calls (e.g., builder.some_element)
          # This maintains backwards compatibility with code that uses
          # builder method_missing for element creation.
          attrs = args.first.is_a?(Hash) ? args.first : {}
          create_and_add_element(method_name.to_s, attributes: attrs, &)
        end

        def respond_to_missing?(_method_name, _include_private = false)
          true
        end
      end
    end
  end
end
