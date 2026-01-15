# frozen_string_literal: true

module Lutaml
  module Model
    # Pure data classes for XML intermediate representation.
    #
    # These classes represent XML structure without serialization logic,
    # allowing transformation to produce XML data that can be serialized
    # by different adapters (Nokogiri, Ox, Oga).
    module XmlDataModel
      # Represents an XML element with namespace, attributes, and children.
      class XmlElement
        # @return [String] Element local name
        attr_reader :name

        # @return [Class, nil] XmlNamespace class (not instance)
        attr_reader :namespace_class

        # @return [Array<XmlAttribute>] Element attributes
        attr_reader :attributes

        # @return [Array<XmlElement, String>] Child elements and text nodes
        attr_reader :children

        # @return [String, nil] Direct text content (for simple elements)
        attr_accessor :text_content

        # @return [Boolean] Whether text content should be wrapped in CDATA section
        attr_accessor :cdata

        # Initialize a new XML element
        #
        # @param name [String] Element local name
        # @param namespace_class [Class, nil] XmlNamespace class
        def initialize(name, namespace_class = nil)
          @name = name
          @namespace_class = namespace_class
          @attributes = []
          @children = []
          @text_content = nil
          @cdata = false
        end

        # Add a child element or text node
        #
        # @param child [XmlElement, String] Child to add
        # @return [self]
        def add_child(child)
          @children << child
          self
        end

        # Add an attribute to this element
        #
        # @param attribute [XmlAttribute] Attribute to add
        # @return [self]
        def add_attribute(attribute)
          @attributes << attribute
          self
        end

        # Check if element has any children
        #
        # @return [Boolean]
        def has_children?
          !@children.empty?
        end

        # Check if element has any attributes
        #
        # @return [Boolean]
        def has_attributes?
          !@attributes.empty?
        end

        # Get qualified name (prefix:name or name)
        #
        # @param prefix [String, nil] Optional prefix override
        # @return [String]
        def qualified_name(prefix = nil)
          if prefix
            "#{prefix}:#{name}"
          elsif namespace_class&.respond_to?(:prefix_default)
            ns_prefix = namespace_class.prefix_default
            ns_prefix ? "#{ns_prefix}:#{name}" : name
          else
            name
          end
        end

        # String representation for debugging
        #
        # @return [String]
        def to_s
          parts = ["<#{qualified_name}"]

          if namespace_class
            parts << " (ns: #{namespace_class})"
          end

          if has_attributes?
            parts << " attrs: #{attributes.length}"
          end

          if text_content
            parts << " text: #{text_content.inspect}"
          elsif has_children?
            parts << " children: #{children.length}"
          end

          parts << ">"
          parts.join
        end

        # Detailed inspection for debugging
        #
        # @return [String]
        def inspect
          "#<#{self.class.name} #{to_s}>"
        end
      end

      # Represents an XML attribute with optional namespace.
      class XmlAttribute
        # @return [String] Attribute local name
        attr_reader :name

        # @return [Class, nil] XmlNamespace class (not instance)
        attr_reader :namespace_class

        # @return [String] Attribute value
        attr_reader :value

        # Initialize a new XML attribute
        #
        # @param name [String] Attribute local name
        # @param value [String] Attribute value
        # @param namespace_class [Class, nil] XmlNamespace class
        def initialize(name, value, namespace_class = nil)
          @name = name
          @value = value
          @namespace_class = namespace_class
        end

        # Get qualified name (prefix:name or name)
        #
        # @param prefix [String, nil] Optional prefix override
        # @return [String]
        def qualified_name(prefix = nil)
          if prefix
            "#{prefix}:#{name}"
          elsif namespace_class&.respond_to?(:prefix_default)
            ns_prefix = namespace_class.prefix_default
            ns_prefix ? "#{ns_prefix}:#{name}" : name
          else
            name
          end
        end

        # String representation for debugging
        #
        # @return [String]
        def to_s
          "#{qualified_name}=\"#{value}\""
        end

        # Detailed inspection for debugging
        #
        # @return [String]
        def inspect
          ns_info = namespace_class ? " (ns: #{namespace_class})" : ""
          "#<#{self.class.name} #{to_s}#{ns_info}>"
        end
      end
    end
  end
end