# frozen_string_literal: true

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
      # @param parent [XmlDataModel::XmlElement] Parent element to add children to
      def initialize(parent)
        @parent = parent
        @context_stack = [parent]
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
          add_xml_fragment_or_raw_content(parent, element_or_string)
        elsif element_or_string.is_a?(::Lutaml::Xml::DataModel::XmlElement)
          parent.add_child(element_or_string)
        else
          raise TypeError,
                "add_element expects a String or XmlElement, got " \
                "#{element_or_string.class}. Call .to_xml on the element first."
        end
        element_or_string
      end

      def add_xml_fragment_or_raw_content(parent, fragment_string)
        require "moxml" unless defined?(Moxml)
        fragment_doc = Moxml.new.parse(fragment_string, fragment: true)
        add_fragment_children_to_parent(fragment_doc, parent)
      rescue LoadError
        append_raw_content(parent, fragment_string)
      end

      def append_raw_content(parent, content)
        existing_raw = parent.raw_content
        parent.raw_content = existing_raw ? existing_raw + content : content
      end

      # Helper method to recursively add parsed XML nodes to parent
      #
      # @param fragment_node [Moxml::Element] Parsed Moxml node
      # @param parent [XmlDataModel::XmlElement] Parent element
      def add_fragment_children_to_parent(fragment_node, parent)
        fragment_node.children.each do |child|
          next unless child.element?

          # Create XmlDataModel element for this element
          element = Lutaml::Xml::DataModel::XmlElement.new(child.name)

          # Check if this element has only text children (no nested elements)
          has_nested_elements = child.children.any?(&:element?)

          # Extract text content from direct text children
          text_children = child.children.select(&:text?)
          if text_children.any?
            text_content = text_children.map(&:content).join
            element.text_content = text_content unless text_content.empty?
          end

          # Copy attributes
          child.attributes.each do |attr|
            xml_attr = Lutaml::Xml::DataModel::XmlAttribute.new(
              attr.name, attr.value
            )
            element.add_attribute(xml_attr)
          end

          # Only recurse if there are nested elements
          # (text content was already set above)
          if has_nested_elements
            add_fragment_children_to_parent(child, element)
          end

          # Add to parent
          parent.add_child(element)
        end
      end
      private :add_xml_fragment_or_raw_content,
              :append_raw_content,
              :add_fragment_children_to_parent

      # Add text to element (mimics old adapter API)
      #
      # @param element [XmlDataModel::XmlElement, CustomMethodWrapper, nil]
      #   Element to add text to. When the wrapper itself or nil is passed,
      #   text is added to the current context element.
      # @param text [String] Text content
      def add_text(element, text)
        target = if element == self || element.nil?
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
        element = self.class.build_element(name, attributes)
        current_context.add_child(element)

        if block_given?
          push_context(element)
          begin
            yield ElementWrapper.new(element, self)
          ensure
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
          use_cdata = cdata.is_a?(Hash) ? cdata[:cdata] || false : cdata
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
          child = CustomMethodWrapper.build_element(name, attributes)
          @element.add_child(child)

          if block_given?
            yield ElementWrapper.new(child, @parent_wrapper)
          end

          child
        end
      end

      # Shared factory: create an XmlElement with optional attributes.
      # Public so ElementWrapper can call it without an instance.
      #
      # @param name [String] Element name
      # @param attributes [Hash] Optional attributes
      # @return [DataModel::XmlElement]
      def self.build_element(name, attributes)
        element = Lutaml::Xml::DataModel::XmlElement.new(name)
        attributes&.each do |attr_name, attr_value|
          attr = Lutaml::Xml::DataModel::XmlAttribute.new(
            attr_name.to_s, attr_value.to_s
          )
          element.add_attribute(attr)
        end
        element
      end
    end
  end
end
