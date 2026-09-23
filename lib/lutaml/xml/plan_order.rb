# frozen_string_literal: true

module Lutaml
  module Xml
    # Reconstructs element_order for ordered/mixed models from the
    # leptris node surface in one native pass, mirroring the
    # interpretive AdapterElement#order contract: text runs, CDATA,
    # comments, PIs, and element entries (local name + namespace
    # uri/prefix) in document order, frozen like the interpretive
    # product.
    module PlanOrder
      TEXT_MARKER = "text"
      CDATA_MARKER = "#cdata-section"
      COMMENT_MARKER = "comment"

      class << self
        def build(node)
          node.children.filter_map { |child| entry_for(child) }
            .each(&:freeze).freeze
        end

        private

        def entry_for(child)
          case child
          when ::Leptris::XML::CDATA
            Element.new("Text", CDATA_MARKER,
                        text_content: child.content, node_type: :cdata)
          when ::Leptris::XML::Text
            Element.new("Text", TEXT_MARKER,
                        text_content: child.text, node_type: :text)
          when ::Leptris::XML::Comment
            Element.new("Comment", COMMENT_MARKER,
                        text_content: child.content, node_type: :comment)
          when ::Leptris::XML::ProcessingInstruction
            Element.new("ProcessingInstruction", child.name,
                        text_content: child.content.to_s.sub(/\A\s+/, ""),
                        node_type: :processing_instruction)
          when ::Leptris::XML::Element
            ns = child.namespace
            # Leptris::XML::Namespace is a single object (href/prefix),
            # not the Nokogiri-style prefix hash — hash accessors blow
            # up ordered+namespaced plan parses.
            Element.new("Element", child.name,
                        node_type: :element,
                        namespace_uri: ns&.href,
                        namespace_prefix: ns&.prefix)
          end
        end
      end
    end
  end
end
