module Lutaml
  module Model
    module Xml
      module Nokogiri
        # EntityResolver provides HTML entity resolution functionality
        # for the Nokogiri adapter.
        #
        # This module handles Issue #5: HTML entity fragmentation in mixed content.
        # When Nokogiri parses entities like &copy;, it creates EntityReference nodes
        # that fragment text content. This module consolidates them back together.
        module EntityResolver
          # HTML entity map for resolving entity references
          #
          # Maps entity names to their Unicode characters.
          # Covers common HTML entities used in documents.
          HTML_ENTITIES = {
            "copy" => "©",
            "reg" => "®",
            "trade" => "™",
            "mdash" => "—",
            "ndash" => "–",
            "rsquo" => "'",
            "lsquo" => "'",
            "rdquo" => '"',
            "ldquo" => '"',
            "hellip" => "…",
            "nbsp" => "\u00A0",
            "amp" => "&",
            "lt" => "<",
            "gt" => ">",
            "quot" => '"',
            "apos" => "'",
          }.freeze

          # Consolidate adjacent text, CDATA, and entity reference nodes into single text node
          #
          # This fixes Issue #5: HTML entity fragmentation in mixed content.
          # When Nokogiri parses entities like &copy;, it creates EntityReference nodes
          # that fragment the text content. This method consolidates them back together.
          #
          # @param nodes [Nokogiri::XML::NodeSet] the child nodes to consolidate
          # @return [Array<Nokogiri::XML::Node>] consolidated nodes with merged text
          def consolidate_text_nodes(nodes)
            result = []
            text_buffer = []

            nodes.each do |child|
              if text_like_node?(child)
                # Accumulate text content, resolving entities
                if child.is_a?(::Nokogiri::XML::EntityReference)
                  # Resolve entity reference to character
                  text_buffer << resolve_entity(child)
                else
                  # Regular text or CDATA node
                  text_buffer << child.text
                end
              else
                # Non-text node encountered
                unless text_buffer.empty?
                  # Create single text node from accumulated text
                  result << create_consolidated_text_node(nodes.first.document, text_buffer.join)
                  text_buffer.clear
                end
                result << child
              end
            end

            # Flush any remaining text
            unless text_buffer.empty?
              result << create_consolidated_text_node(nodes.first.document, text_buffer.join)
            end

            result
          end

          # Resolve an entity reference to its character
          #
          # @param entity_ref [::Nokogiri::XML::EntityReference] the entity reference node
          # @return [String] the resolved character or original entity if unknown
          def resolve_entity(entity_ref)
            entity_name = entity_ref.name

            # Check if it's a numeric character reference (#xxx or #xHH)
            if entity_name.start_with?("#")
              # Numeric character reference
              if entity_name.start_with?("#x")
                # Hexadecimal
                code = entity_name[2..-1].to_i(16)
              else
                # Decimal
                code = entity_name[1..-1].to_i(10)
              end
              return [code].pack("U")
            end

            # Look up in HTML entities map
            HTML_ENTITIES[entity_name] || "&#{entity_name};"
          end

          # Check if node should be consolidated with adjacent text
          #
          # Only text nodes and entity references should be consolidated.
          # CDATA nodes must remain separate to preserve their special semantics.
          #
          # @param node [::Nokogiri::XML::Node] the node to check
          # @return [Boolean] true if node is text or entity reference (NOT CDATA)
          def text_like_node?(node)
            node.text? || node.is_a?(::Nokogiri::XML::EntityReference)
          end

          # Create a new text node with given content
          #
          # @param document [::Nokogiri::XML::Document] the document to attach to
          # @param text [String] the text content
          # @return [::Nokogiri::XML::Text] new text node
          def create_consolidated_text_node(document, text)
            ::Nokogiri::XML::Text.new(text, document)
          end
        end
      end
    end
  end
end