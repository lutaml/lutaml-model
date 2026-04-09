# frozen_string_literal: true

require "moxml"
require "moxml/adapter/oga"

module Lutaml
  module Xml
    module Oga
      # Wrapper around Moxml::Document for the Oga adapter.
      # All XML operations go through moxml — no native ::Oga::XML::* usage.
      #
      # Implements the same interface as Moxml::Element for methods the builder
      # uses, so the builder doesn't need to branch on Document vs Element.
      # Element-level operations ([], []=, attributes) delegate to root.
      class Document
        attr_reader :moxml_doc, :context

        def initialize(_options = {})
          @context = Moxml.new(:oga)
          @moxml_doc = @context.create_document
        end

        def root
          @moxml_doc.root
        end

        def children
          @moxml_doc.children
        end

        def add_child(node)
          @moxml_doc.add_child(node)
        end

        # Delegate attribute access to root element
        def [](name)
          root&.[](name)
        end

        def []=(name, value)
          root&.[]=(name, value)
        end

        def attributes
          root&.attributes || []
        end

        def text(value = nil)
          text_node = @moxml_doc.create_text(value.to_s)
          @moxml_doc.add_child(text_node)
          self
        end

        def to_xml(options = {})
          @moxml_doc.to_xml(options)
        end

        def inner_text
          root&.inner_text
        end

        def parent
          nil
        end

        def method_missing(method_name, *, &)
          return @moxml_doc.public_send(method_name, *, &) if @moxml_doc.respond_to?(method_name)

          super
        end

        def respond_to_missing?(method_name, include_private = false)
          @moxml_doc.respond_to?(method_name, include_private) || super
        end
      end
    end
  end
end
