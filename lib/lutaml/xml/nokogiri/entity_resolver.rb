module Lutaml
  module Xml
    module Nokogiri
      # EntityResolver handles EntityReference nodes produced by Nokogiri
      # when parsing XML with undefined entities (e.g. &nbsp;, &copy;).
      #
      # We do NOT resolve these entities — we pass them through as literal
      # "&name;" text so they survive round-trips. Resolution is the job
      # of the XML parser, not the data model.
      module EntityResolver
        # Consolidate adjacent text and CDATA nodes into single text nodes.
        # EntityReference nodes are kept as separate nodes to preserve entity syntax.
        #
        # @param nodes [Nokogiri::XML::NodeSet] the child nodes to consolidate
        # @return [Array<Nokogiri::XML::Node>] consolidated nodes with merged text
        def consolidate_text_nodes(nodes)
          result = []
          text_buffer = []

          return result if nodes.nil? || nodes.empty?

          nodes.each do |child|
            if child.is_a?(::Nokogiri::XML::EntityReference)
              # Flush any pending text first - EntityReference stays as separate node
              unless text_buffer.empty?
                document = nodes.first&.document
                if document
                  result << create_consolidated_text_node(document,
                                                      text_buffer.join)
                end
                text_buffer.clear
              end
              # Keep EntityReference as separate node - do NOT merge into text
              result << child
            elsif text_like_node?(child)
              # Only consolidate Text/CDATA nodes, not EntityReference
              text_buffer << child.text
            else
              # Non-text node - flush pending text first
              unless text_buffer.empty?
                document = nodes.first&.document
                if document
                  result << create_consolidated_text_node(document,
                                                          text_buffer.join)
                end
                text_buffer.clear
              end
              result << child
            end
          end

          unless text_buffer.empty?
            document = nodes.first&.document
            if document
              result << create_consolidated_text_node(document,
                                                      text_buffer.join)
            end
          end

          result
        end

        # Check if node should be consolidated with adjacent text
        #
        # @param node [::Nokogiri::XML::Node] the node to check
        # @return [Boolean] true if node is text or entity reference
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
