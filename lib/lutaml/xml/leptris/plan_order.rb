# frozen_string_literal: true

module Lutaml
  module Xml
    module Leptris
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

        # The per-parse intern table's entry ceiling: names, namespace
        # URIs, prefixes and short text runs repeat across millions of
        # entries on large documents; the table collapses them to
        # distinct strings so the summaries retain one copy instead of
        # one FFI mint per child. Only strings up to INTERN_LIMIT are
        # interned — longer text is document data and stays un-interned
        # to keep the table bounded.
        INTERN_LIMIT = 32

        class << self
          def build(node, intern = {})
            node.children.filter_map { |child| entry_for(child, intern) }
              .each(&:freeze).freeze
          end

          private

          def intern_string(intern, value)
            return value if value.nil?

            intern[value] ||= value
          end

          def entry_for(child, intern)
            case child
            when ::Leptris::XML::CDATA
              Element.new("Text", CDATA_MARKER,
                          text_content: child.content, node_type: :cdata)
            when ::Leptris::XML::Text
              text = child.text
              text = intern_string(intern, text) if text.length <= INTERN_LIMIT
              Element.new("Text", TEXT_MARKER,
                          text_content: text, node_type: :text)
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
              Element.new("Element", intern_string(intern, child.name),
                          node_type: :element,
                          namespace_uri: intern_string(intern, ns&.href),
                          namespace_prefix: intern_string(intern, ns&.prefix))
            end
          end
        end
      end
    end
  end
end
