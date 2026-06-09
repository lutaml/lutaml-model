# frozen_string_literal: true

module Lutaml
  module Xml
    module Adapter
      # Base class for XML adapters providing shared functionality.
      #
      # This class extracts common code from NokogiriAdapter, OxAdapter,
      # OgaAdapter, and RexmlAdapter to reduce duplication and ensure
      # consistent behavior across adapters.
      #
      # Subclasses must implement:
      # - MOXML_ADAPTER - Moxml adapter implementation for parsing
      # - BUILDER_CLASS - Builder implementation for serialization
      # - PARSED_ELEMENT_CLASS - Adapter element class returned by parsing
      #
      # @abstract Subclass and implement required methods
      class BaseAdapter < Document
        extend DocTypeExtractor
        extend AdapterHelpers
        extend XmlParser
        include DeclarationHandler
        include PolymorphicValueHandler
        include NamespaceUriCollector
        include XmlSerializer
        include PlanBasedBuilder

        EMPTY_DOCUMENT_ERROR_MESSAGE = "Document has no root element. " \
                                       "The XML may be empty, contain only whitespace, " \
                                       "or consist only of an XML declaration."
        EMPTY_DOCUMENT_ERROR_TYPE = :invalid_format
        PARSE_ERROR_CLASS = nil

        # Convert a Formal Public Identifier (FPI) to a URN per RFC 3151.
        # FPI examples: "-//OASIS//DTD XML Exchange Table Model 19990315//EN"
        # Returns nil if the string is not an FPI.
        #
        # RFC 3151 format: urn:publicid:prefix:+/-//registrant//description//language//
        # Conversion: replace spaces with +, prepend "urn:publicid:"
        def self.fpi_to_urn(fpi)
          return nil unless fpi.is_a?(String) && fpi.start_with?("-//", "+//")

          # Replace spaces with + per RFC 3151
          normalized = fpi.gsub(" ", "+")

          "urn:publicid:#{normalized}"
        end

        # Detect if a string is an FPI (Formal Public Identifier), not a valid namespace URI.
        # FPIs start with -// or +// (SGML-style, not a URI scheme).
        def self.fpi?(uri)
          uri.is_a?(String) && uri.start_with?("-//", "+//")
        end

        def self.extract_document_processing_instructions(moxml_doc)
          pis = []
          root = moxml_doc.root
          moxml_doc.children.each do |child|
            break if child == root
            next unless child.is_a?(Moxml::ProcessingInstruction)

            pis << Lutaml::Xml::DataModel::XmlProcessingInstruction.new(
              child.target, child.content.to_s.strip
            )
          end
          pis
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
          elsif @encoding && @encoding.to_s.upcase != "ASCII-8BIT"
            @encoding
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
          return false unless element.is_a?(Lutaml::Model::Serialize)

          mapper_class = options[:mapper_class]
          xml_mapping = mapper_class&.mappings_for(:xml)

          # Class mapping is the authoritative source for ordered/mixed.
          # Instance @ordered/@mixed are stale after class definition changes.
          if xml_mapping&.mixed_content? || xml_mapping&.ordered?
            return !element.element_order.nil? && !element.element_order.empty?
          end

          return options[:mixed_content] if options.key?(:mixed_content)

          false
        end

        def order
          root.order
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

          delegated_obj = element.public_send(rule.delegate)
          return nil if delegated_obj.nil?

          delegated_obj.class.attributes[rule.to]
        end

        # Get attribute value for an element and rule
        #
        # @param element [Object] the model instance
        # @param rule [MappingRule] the mapping rule
        # @return [Object, nil] the attribute value or nil if delegate is nil
        def attribute_value_for(element, rule)
          return element.public_send(rule.to) unless rule.delegate

          delegate_obj = element.public_send(rule.delegate)
          return nil if delegate_obj.nil?

          delegate_obj.public_send(rule.to)
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
            apply_custom_to(content_rule, element, xml, mapper_class)
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

          attribute_values(element) do |attr|
            if schema_location_attribute?(attr)
              result["__schema_location"] = {
                namespace: attr.namespace,
                prefix: attribute_namespace_prefix(attr),
                schema_location: attr.value,
              }
            else
              result[attribute_hash_name(attr)] = attr.value
            end
          end

          result
        end

        private

        def attribute_values(element, &)
          element.attributes.each_value(&)
        end

        def schema_location_attribute?(attr)
          attr_name = if attr.is_a?(Lutaml::Xml::XmlAttribute)
                        attr.unprefixed_name
                      else
                        attr.name
                      end
          attr_name == "schemaLocation"
        end

        def attribute_namespace_prefix(attr)
          if attr.is_a?(Lutaml::Xml::XmlAttribute)
            attr.namespace_prefix
          else
            attr.namespace&.prefix
          end
        end

        def attribute_hash_name(attr)
          if attr.is_a?(Lutaml::Xml::XmlAttribute)
            attr.namespaced_name
          else
            self.class.namespaced_attr_name(attr)
          end
        end
      end
    end
  end
end
