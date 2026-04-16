require "moxml"
require "nokogiri"

module Lutaml
  module Xml
    module Builder
      # Moxml DOM-based builder for XML construction.
      #
      # Moxml Limitation: .native usage
      # --------------------------------
      # This builder uses .native to access underlying Nokogiri objects in
      # several places because of two Moxml limitations:
      #
      # 1. Cross-document node creation: Moxml's create_element/create_text/etc.
      #    create nodes in a fresh Nokogiri::XML::Document each time. When these
      #    nodes are added to a different document via add_child, they silently
      #    fail to appear in serialized output. We work around this by creating
      #    native Nokogiri nodes directly in the builder's document.
      #
      # 2. namespace_scopes: Moxml does not expose Element#namespace_scopes
      #    (the list of all in-scope namespaces including inherited ones).
      #    We access element.native.namespace_scopes to resolve namespace
      #    prefixes from parent declarations.
      #
      # 3. Namespace assignment: Moxml's Element#namespace= expects a Moxml
      #    Namespace or Hash, but namespace_scopes returns native Nokogiri
      #    namespace objects. We use element.native.namespace= to set them.
      #
      # 4. Serialization: We use .native.to_xml for consistent output format
      #    (self-closing empty elements, character reference preservation).
      #
      # TODO: Remove .native usage once Moxml supports:
      #   - Same-document node creation (create_element in owning doc)
      #   - Element#namespace_scopes (in-scope namespace query)
      #   - Element#namespace= accepting native namespace objects
      #   - SaveOptions control for self-closing empty elements
      class Nokogiri
        def self.build(options = {})
          context = Moxml.new do |config|
            config.namespace_uri_mode = :lenient
          end

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
          # Create element in the builder's native document to avoid
          # cross-document issues (see class comment about Moxml limitation #1).
          native_el = ::Nokogiri::XML::Element.new(name, @doc.native)
          el = Moxml::Element.wrap(native_el, @context)
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

          # Create element in the builder's native document for proper namespace scoping.
          # Use local name only — Nokogiri::XML::Element.new doesn't interpret colons
          # as namespace separators. The namespace prefix is applied via namespace= later.
          native_doc = @doc.native
          native_el = ::Nokogiri::XML::Element.new(element_name, native_doc)
          el = Moxml::Element.wrap(native_el, @context)

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
            ns = el.native.namespace_scopes.find { |n| n.prefix == prefix }
            el.native.namespace = ns if ns
          elsif !prefix_unset && prefix.nil?
            # Explicitly no prefix (prefix: nil) — blank namespace
            el.native.namespace = nil
          else
            # For unprefixed elements, check if there's a default namespace
            default_ns = el.native.namespace_scopes.find { |n| n.prefix.nil? }
            el.native.namespace = default_ns if default_ns
          end

          # Add to parent
          if current_element.is_a?(Moxml::Document)
            current_element.root = el
          else
            current_element.add_child(el)

            # After adding to parent, resolve namespace from parent's scopes
            # (Nokogiri builder docs automatically propagate parent namespace to children)
            # For explicitly prefixed elements not yet resolved, try parent's scopes
            if !prefix_unset && prefix && el.native.namespace.nil?
              ns = el.native.namespace_scopes.find { |n| n.prefix == prefix }
              el.native.namespace = ns if ns
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

          native_target = target.is_a?(Moxml::Node) ? target.native : target
          fragment = ::Nokogiri::XML.fragment(content)
          native_target.add_child(fragment)
        end

        def add_text(element, text, cdata: false)
          return add_cdata(element, text) if cdata

          target = if element.is_a?(self.class)
                     element.current_element
                   else
                     element
                   end

          # Create text node in the same native document to avoid cross-document issues
          native_target = target.is_a?(Moxml::Node) ? target.native : target
          text_node = ::Nokogiri::XML::Text.new(text.to_s, native_target.document)
          native_target.add_child(text_node)
        end

        def add_cdata(element, value)
          target = if element.is_a?(self.class)
                     element.current_element
                   else
                     element
                   end

          # Create CDATA node in the same native document
          native_target = target.is_a?(Moxml::Node) ? target.native : target
          cdata_node = ::Nokogiri::XML::CDATA.new(native_target.document, value.to_s)
          native_target.add_child(cdata_node)
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
