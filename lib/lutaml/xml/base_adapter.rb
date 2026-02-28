# frozen_string_literal: true

module Lutaml
  module Xml
      # Base class for XML adapters providing shared functionality.
      #
      # This class extracts common code from NokogiriAdapter, OxAdapter,
      # OgaAdapter, and RexmlAdapter to reduce duplication and ensure
      # consistent behavior across adapters.
      #
      # Subclasses must implement:
      # - self.parse(xml, options) - Parse XML string to document
      # - to_xml(options) - Serialize document to XML string
      #
      # @abstract Subclass and implement required methods
      class BaseAdapter < Document
      include DeclarationHandler
      include PolymorphicValueHandler

      # Class methods for element inspection
      # These are shared across all adapters

      # Get the local name of an element
      #
      # @param element [Object] the element to inspect
      # @return [String] the element's local name
      def self.name_of(element)
      element.name
      end

      # Get the prefixed name of an element
      #
      # @param node [Object] the element node
      # @return [String] the prefixed name (prefix:localname)
      def self.prefixed_name_of(node)
      node.prefixed_name
      end

      # Get the text content of an element
      #
      # @param element [Object] the element to get text from
      # @return [String] the text content
      def self.text_of(element)
      element.text
      end

      # Get the namespaced name of an element
      #
      # @param element [Object] the element to inspect
      # @return [String] the namespaced name
      def self.namespaced_name_of(element)
      element.namespaced_name
      end

      # Get the order of child elements
      #
      # @param element [Object] the parent element
      # @return [Array] ordered list of children
      def self.order_of(element)
      element.order
      end

      # Build a namespaced attribute name
      #
      # @param prefix [String, nil] the namespace prefix
      # @param name [String] the attribute name
      # @return [String] the qualified attribute name
      def self.namespaced_attr_name(prefix, name)
      prefix ? "#{prefix}:#{name}" : name
      end

      # Build a namespaced element name
      #
      # @param namespace_uri [String, nil] the namespace URI
      # @param prefix [String, nil] the namespace prefix
      # @param name [String] the element name
      # @return [String] the qualified element name
      def self.namespaced_name(namespace_uri, prefix, name)
      if namespace_uri
        prefix ? "#{prefix}:#{name}" : name
      else
        name
      end
      end

      # Instance methods shared across adapters

      # Determine encoding for XML output
      # Returns nil when encoding is explicitly set to nil (to not set encoding at all)
      #
      # @param options [Hash] serialization options
      # @return [String, nil] the encoding to use, or nil to skip setting encoding
      def determine_encoding(options)
      if options.key?(:encoding)
        # Return nil if encoding is explicitly nil (don't set encoding)
        # Return the value otherwise
        options[:encoding]
      elsif options.key?(:parse_encoding)
        options[:parse_encoding]
      else
        "UTF-8"
      end
      end

      # Check if an element should be rendered
      #
      # @param rule [MappingRule] the mapping rule
      # @param element [Object] the model instance
      # @param value [Object] the value to check
      # @return [Boolean] true if the element should be rendered
      def render_element?(rule, element, value)
      rule.render?(value, element)
      end

      # Check if element has ordered content
      #
      # @param element [Object] the model instance
      # @param options [Hash] serialization options
      # @return [Boolean] true if element has ordered content
      def ordered?(element, options = {})
      return false unless element.respond_to?(:element_order)
      return element.ordered? if element.respond_to?(:ordered?)
      return options[:mixed_content] if options.key?(:mixed_content)

      mapper_class = options[:mapper_class]
      mapper_class ? mapper_class.mappings_for(:xml).mixed_content? : false
      end

      # Get attribute definition for an element and rule
      #
      # @param element [Object] the model instance
      # @param rule [MappingRule] the mapping rule
      # @param mapper_class [Class, nil] optional mapper class
      # @return [Attribute, nil] the attribute definition
      def attribute_definition_for(element, rule, mapper_class: nil)
      klass = mapper_class || element.class
      return klass.attributes[rule.to] unless rule.delegate

      delegated_obj = element.send(rule.delegate)
      return nil if delegated_obj.nil?

      delegated_obj.class.attributes[rule.to]
      end

      # Get attribute value for an element and rule
      #
      # @param element [Object] the model instance
      # @param rule [MappingRule] the mapping rule
      # @return [Object] the attribute value
      def attribute_value_for(element, rule)
      return element.send(rule.to) unless rule.delegate

      element.send(rule.delegate).send(rule.to)
      end

      # Process content mapping for an element
      #
      # @param element [Object] the model instance
      # @param content_rule [MappingRule] the content mapping rule
      # @param xml [Builder] the XML builder
      # @param mapper_class [Class] the mapper class
      def process_content_mapping(element, content_rule, xml, mapper_class)
      return unless content_rule

      if content_rule.custom_methods[:to]
        mapper_class.new.send(
          content_rule.custom_methods[:to],
          element,
          xml.parent,
          xml,
        )
      else
        text = content_rule.serialize(element)
        text = text.join if text.is_a?(Array)

        xml.add_text(xml, text, cdata: content_rule.cdata)
      end
      end

      # Build attributes hash from element attributes
      #
      # @param element [Object] the element with attributes
      # @return [Hash] hash of attribute names to values
      def attributes_hash(element)
      result = Lutaml::Model::MappingHash.new

      element.attributes.each_value do |attr|
        if attr.unprefixed_name == "schemaLocation"
          result["__schema_location"] = {
            namespace: attr.namespace,
            prefix: attr.namespace_prefix,
            schema_location: attr.value,
          }
        else
          result[attr.namespaced_name] = attr.value
        end
      end

      result
      end

      # Add text content to XML builder
      #
      # @param xml [Builder] the XML builder
      # @param value [Object] the value to add
      # @param attribute [Attribute, nil] the attribute definition
      # @param cdata [Boolean] whether to use CDATA
      def add_value(xml, value, attribute, cdata: false)
      if !value.nil?
        if attribute.nil?
          # For delegated attributes where attribute is nil, just use the raw value
          xml.add_text(xml, value.to_s, cdata: cdata)
        elsif attribute.transform.is_a?(Class) && attribute.transform < Lutaml::Model::ValueTransformer
          # Value has already been transformed, use it directly
          xml.add_text(xml, value.to_s, cdata: cdata)
        else
          # Normal serialization through attribute type system
          serialized_value = attribute.serialize(value, :xml, register)
          if attribute.raw?
            xml.add_xml_fragment(xml, value)
          elsif serialized_value.is_a?(Hash)
            serialized_value.each do |key, val|
              xml.create_and_add_element(key) do |element|
                element.text(val)
              end
            end
          else
            xml.add_text(xml, serialized_value, cdata: cdata)
          end
        end
      end
      end
      end
  end
end
