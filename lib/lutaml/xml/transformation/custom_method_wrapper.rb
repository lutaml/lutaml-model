# frozen_string_literal: true

require_relative "../data_model"

module Lutaml
  module Xml
      # Wrapper for custom method compatibility with XmlDataModel.
      #
      # Custom methods use the old adapter API (doc.create_and_add_element),
      # but the new transformation works with XmlDataModel. This wrapper
      # bridges the gap by implementing the old adapter interface while
      # working with XmlDataModel elements under the hood.
      #
      # The wrapper tracks a "current context" element. When create_and_add_element
      # is called with a block, the new element becomes the context for the duration
      # of the block, allowing nested element creation.
      class CustomMethodWrapper
      # Initialize the wrapper
      #
      # @param parent [XmlDataModel::XmlElement] Parent element to add children to
      # @param rule [CompiledRule] The transformation rule
      def initialize(parent, rule)
      @parent = parent
      @rule = rule
      @context_stack = [parent] # Stack of context elements for nested creation
      end

      # Get the current context element (top of stack)
      #
      # @return [XmlDataModel::XmlElement] Current context element
      def current_context
      @context_stack.last
      end

      # Push a new context onto the stack
      #
      # @param element [XmlDataModel::XmlElement] New context element
      def push_context(element)
      @context_stack.push(element)
      end

      # Pop the current context from the stack
      #
      # @return [XmlDataModel::XmlElement] The popped context
      def pop_context
      @context_stack.pop if @context_stack.size > 1
      end

      # Create an element (mimics old adapter API)
      #
      # @param name [String] Element name
      # @return [XmlDataModel::XmlElement] The created element
      def create_element(name)
      Lutaml::Xml::DataModel::XmlElement.new(name)
      end

      # Add an element to the current context (mimics old adapter API)
      #
      # @param parent_or_element [XmlDataModel::XmlElement] Parent element or element to add
      # @param element_or_string [XmlDataModel::XmlElement, String, nil] Element to add or string content (nil if parent_or_element is the element)
      # @return [XmlDataModel::XmlElement] The added element
      def add_element(parent_or_element, element_or_string = nil)
      # Handle overloaded API: add_element(element) or add_element(parent, element)
      if element_or_string.nil?
        # Single argument: parent_or_element is the element to add to current context
        element = parent_or_element
        current_context.add_child(element)
        return element
      end

      parent = parent_or_element

      if element_or_string.is_a?(String)
        # Parse XML string and add as child elements
        # This handles cases like doc.add_element(parent, "<city>B</city>")
        # We need to parse the XML and add each element as a proper child
        # to maintain correct ordering in the output
        begin
          # Use Nokogiri to parse the XML fragment
          require "nokogiri" unless defined?(Nokogiri)
          fragment = ::Nokogiri::XML.fragment(element_or_string)

          # Convert each Nokogiri element to our XmlDataModel format
          # and add as proper children to maintain ordering
          add_nokogiri_children_to_parent(fragment, parent)
        rescue StandardError
          # Fallback: if parsing fails, store as raw content
          existing_raw = parent.instance_variable_get(:@raw_content)
          if existing_raw
            parent.instance_variable_set(:@raw_content,
                                         existing_raw + element_or_string)
          else
            parent.instance_variable_set(:@raw_content, element_or_string)
          end
        end
      else
        # Add as child element
        parent.add_child(element_or_string)
      end
      element_or_string
      end

      # Helper method to recursively add Nokogiri nodes to parent
      #
      # @param nokogiri_node [::Nokogiri::XML::Node] Nokogiri node
      # @param parent [XmlDataModel::XmlElement] Parent element
      def add_nokogiri_children_to_parent(nokogiri_node, parent)
      nokogiri_node.children.each do |child|
        case child
        when ::Nokogiri::XML::Element
          # Create XmlDataModel element for this Nokogiri element
          element = Lutaml::Xml::DataModel::XmlElement.new(child.name)

          # Check if this element has only text children (no nested elements)
          has_nested_elements = child.children.any?(::Nokogiri::XML::Element)

          # Extract text content from direct text children
          text_children = child.children.select do |c|
            c.is_a?(::Nokogiri::XML::Text)
          end
          if text_children.any?
            text_content = text_children.map(&:text).join
            element.text_content = text_content unless text_content.empty?
          end

          # Copy attributes
          child.attributes.each_value do |attr|
            xml_attr = Lutaml::Xml::DataModel::XmlAttribute.new(
              attr.name, attr.value
            )
            element.add_attribute(xml_attr)
          end

          # Only recurse if there are nested elements
          # (text content was already set above)
          if has_nested_elements
            add_nokogiri_children_to_parent(child, element)
          end

          # Add to parent
          parent.add_child(element)
        end
      end
      end

      # Add text to element (mimics old adapter API)
      #
      # @param element [XmlDataModel::XmlElement, CustomMethodWrapper, nil] Element to add text to
      # @param text [String] Text content
      def add_text(element, text)
      # Handle case where element is the wrapper itself (for content mapping)
      # or when element is nil (add to current context)
      target = if element.is_a?(CustomMethodWrapper) || element.nil?
                 current_context
               else
                 element
               end
      target.text_content = text
      end

      # Add attribute to element (mimics old adapter API)
      #
      # @param element [XmlDataModel::XmlElement] Element to add attribute to
      # @param name [String] Attribute name
      # @param value [String] Attribute value
      def add_attribute(element, name, value)
      attr = Lutaml::Xml::DataModel::XmlAttribute.new(name.to_s,
                                                           value.to_s)
      element.add_attribute(attr)
      end

      # Create and add an element (mimics old adapter API)
      #
      # When called with a block, the new element becomes the context for nested
      # operations inside the block.
      #
      # @param name [String] Element name
      # @param attributes [Hash] Optional attributes to add to the element
      # @yield [ElementWrapper] The created element for customization
      # @return [XmlElement] The created element
      def create_and_add_element(name, attributes: {})
      # Create XmlDataModel element
      element = Lutaml::Xml::DataModel::XmlElement.new(name)

      # Add attributes if provided
      attributes&.each do |attr_name, attr_value|
        attr = Lutaml::Xml::DataModel::XmlAttribute.new(
          attr_name.to_s, attr_value.to_s
        )
        element.add_attribute(attr)
      end

      # Add to current context
      current_context.add_child(element)

      if block_given?
        # Push this element as the new context for nested operations
        push_context(element)

        begin
          # Create wrapper for the element
          wrapped_element = ElementWrapper.new(element, self)

          # Yield for customization (e.g., adding text, more nested elements)
          yield wrapped_element
        ensure
          # Restore previous context
          pop_context
        end
      end

      element
      end

      # Wrapper for XmlDataModel::XmlElement that adds compatibility methods
      # expected by custom serialization methods
      class ElementWrapper
      def initialize(element, parent_wrapper = nil)
        @element = element
        @parent_wrapper = parent_wrapper
      end

      # Add text content to the element (old adapter API)
      #
      # @param _self [XmlElement] Self parameter (ignored, for compatibility)
      # @param text [String] Text content
      # @param cdata [Boolean, Hash] Whether to use CDATA (true or {cdata: true})
      def add_text(_self, text, cdata: false)
        # Handle both cdata: true and cdata: {cdata: true} formats
        use_cdata = if cdata.is_a?(Hash)
                      cdata[:cdata] || false
                    else
                      cdata
                    end

        @element.text_content = text
        @element.cdata = use_cdata
      end

      # Create and add a child element (old adapter API)
      #
      # @param name [String] Element name
      # @param attributes [Hash] Optional attributes to add to the element
      # @yield [ElementWrapper] The created element for customization
      # @return [XmlElement] The created element
      def create_and_add_element(name, attributes: {})
        # Create XmlDataModel element
        child = Lutaml::Xml::DataModel::XmlElement.new(name)

        # Add attributes if provided
        attributes&.each do |attr_name, attr_value|
          attr = Lutaml::Xml::DataModel::XmlAttribute.new(
            attr_name.to_s, attr_value.to_s
          )
          child.add_attribute(attr)
        end

        # Add to this element
        @element.add_child(child)

        if block_given?
          # Wrap the child and yield
          wrapped_child = ElementWrapper.new(child, @parent_wrapper)
          yield wrapped_child
        end

        child
      end
      end
      end
  end
end
