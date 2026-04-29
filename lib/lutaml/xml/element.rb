module Lutaml
  module Xml
    class Element
      include Lutaml::Model::Liquefiable

      attr_reader :type, :name, :text_content, :node_type, :namespace_uri,
                  :namespace_prefix

      # Create a new Element for order tracking
      #
      # @param type [String] "Text" or "Element" (deprecated, use node_type)
      # @param name [String] The element name or text marker
      # @param text_content [String, nil] Actual text content for text nodes
      # @param node_type [Symbol, nil] The node type (:text, :cdata, :element, :comment, :processing_instruction)
      # @param namespace_uri [String, nil] The namespace URI of this element
      # @param namespace_prefix [String, nil] The namespace prefix of this element
      def initialize(type, name, text_content: nil, node_type: nil,
                     namespace_uri: nil, namespace_prefix: nil)
        @type = type # "Text" or "Element" - deprecated, kept for backward compatibility
        @name = name
        # For text nodes, store both marker ("text") and actual content
        @text_content = text_content || name
        # Infer node_type from type for backward compatibility if not provided
        @node_type = node_type || infer_node_type(type, name)
        @namespace_uri = namespace_uri
        @namespace_prefix = namespace_prefix
      end

      # Check if this is a text content node (not CDATA)
      def text?
        @node_type == :text
      end

      # Check if this is a CDATA section
      def cdata?
        @node_type == :cdata
      end

      # Check if this is a regular element
      def element?
        @node_type == :element
      end

      def processing_instruction?
        @node_type == :processing_instruction
      end

      def element_tag
        @name unless text? || cdata? || processing_instruction?
      end

      def eql?(other)
        return false unless other.is_a?(self.class)

        # Only compare type and name for backward compatibility
        # text_content is for internal round-trip use only
        @type == other.type && @name == other.name
      end

      def to_liquid
        self.class.validate_liquid!
        self.class.register_liquid_drop_class unless self.class.drop_class

        register_liquid_methods
        self.class.drop_class.new(self)
      end

      alias == eql?

      private

      # Infer node_type from legacy type/name parameters
      def infer_node_type(type, name)
        return :text if type == "Text" && name != "#cdata-section"
        return :cdata if name == "#cdata-section" || (type == "Text" && name == "#cdata-section")
        return :processing_instruction if type == "ProcessingInstruction"

        :element
      end

      def register_liquid_methods
        %i[text? element_tag type name text_content node_type
           cdata? processing_instruction? namespace_uri namespace_prefix].each do |attr_name|
          self.class.register_drop_method(attr_name)
        end

        self.class.drop_class.define_method(:==) do |other|
          return false unless other.is_a?(self.class)

          # Only compare type and name for backward compatibility
          __getobj__.type == other.__getobj__.type && __getobj__.name == other.__getobj__.name
        end
      end
    end
  end
end
