# frozen_string_literal: true

require_relative "../document"
require_relative "../declaration_handler"
require_relative "../polymorphic_value_handler"
require_relative "../sax_handler"

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
      # - self.parse(xml, options) - Parse XML string to document
      # - to_xml(options) - Serialize document to XML string
      #
      # @abstract Subclass and implement required methods
      class BaseAdapter < Document
        include DeclarationHandler
        include PolymorphicValueHandler

        # Class methods for element inspection
        # These are shared across all adapters

        # Returns the Moxml adapter symbol for this adapter class.
        # Subclasses must override this method.
        #
        # @return [Symbol] the Moxml adapter name (e.g., :nokogiri, :ox, :oga, :rexml)
        def self.moxml_adapter_name
          raise NotImplementedError,
                "#{name} must implement self.moxml_adapter_name"
        end

        # Preprocess XML string before SAX parsing.
        # Override in subclasses that need encoding normalization or entity
        # marker substitution. Default is no-op.
        #
        # @param xml [String] the XML string to preprocess
        # @return [String] the preprocessed XML string
        def self.preprocess_for_sax(xml)
          xml
        end

        # Restore adapter-specific preprocessing markers in text nodes.
        # Override in adapters that use entity markers (e.g., Nokogiri).
        def self.restore_sax_text(text)
          text
        end

        # Walk the SAX-parsed XmlElement tree and restore adapter-specific
        # preprocessing markers (e.g., entity markers) in text/cdata nodes
        # and attribute values.
        #
        # Text nodes: restore named entity markers (&name;).
        # Attribute values: restore markers AND resolve any unresolved numeric
        #   character references (e.g., &#38; in Nokogiri SAX).
        def self.restore_sax_text_in_tree(element)
          return unless element

          if (element.text? || element.cdata?) && element.text
            element.text = restore_sax_text(element.text)
          end

          # Attributes: restore entity markers AND resolve numeric refs
          # to their character equivalents (attributes are plain strings).
          element.attributes.each_value do |attr|
            attr.value = restore_sax_attr(attr.value) if attr.value.is_a?(String)
          end

          element.children&.each { |child| restore_sax_text_in_tree(child) }
        end

        # Restore attribute values: entity markers are restored as-is,
        # numeric character references are resolved to characters.
        # Override in adapters that need different behavior.
        def self.restore_sax_attr(text)
          restore_sax_text(text)
        end

        # Parse XML using SAX for better read-only performance.
        # Builds an XmlElement tree directly from SAX events,
        # avoiding the intermediate DOM tree created by #parse.
        # Falls back to DOM parsing if SAX rejects the XML
        # (e.g., technically-invalid namespace bindings that DOM tolerates).
        #
        # @param xml [String] The XML string to parse
        # @param options [Hash] Parse options
        # @return [BaseAdapter] Adapter wrapping a XmlElement root
        def self.parse_sax(xml, options = {})
          enc = encoding(xml, options)
          original_xml = xml
          xml = preprocess_for_sax(xml)

          # If preprocessing transcoded to UTF-8, fix the XML declaration
          # so the parser doesn't misinterpret UTF-8 bytes as the original
          # encoding (e.g., ISO-8859-1).
          if xml.encoding == Encoding::UTF_8 && original_xml.encoding != Encoding::UTF_8
            xml = xml.sub(/(encoding\s*=\s*["'])[A-Za-z0-9_-]+(["'])/,
                          '\1UTF-8\2')
          end

          context = Moxml.new(moxml_adapter_name)
          handler = Lutaml::Xml::SaxHandler.new
          context.sax_parse(xml, handler)

          unless handler.root
            raise Lutaml::Model::InvalidFormatError.new(
              :xml,
              "Document has no root element. " \
              "The XML may be empty, contain only whitespace, " \
              "or consist only of an XML declaration.",
            )
          end

          # Restore adapter-specific preprocessing (e.g., entity markers) in text nodes
          restore_sax_text_in_tree(handler.root)

          doctype_info = extract_doctype_from_xml(original_xml)
          xml_decl_info = DeclarationHandler.extract_xml_declaration(original_xml)

          new(handler.root, enc, doctype: doctype_info,
                                 xml_declaration: xml_decl_info)
        rescue Moxml::ParseError
          # SAX is stricter than DOM (e.g., rejects xml: namespace on wrong
          # prefix). Fall back to DOM which tolerates these cases.
          parse(original_xml, options)
        end

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
        # @return [Object, nil] the attribute value or nil if delegate is nil
        def attribute_value_for(element, rule)
          return element.send(rule.to) unless rule.delegate

          delegate_obj = element.send(rule.delegate)
          return nil if delegate_obj.nil?

          delegate_obj.send(rule.to)
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

        # Get child plan from parent plan (unified access for both object and hash plans)
        #
        # @param plan [DeclarationPlan, Hash, nil] the parent plan
        # @param attr_name [Symbol] the attribute name
        # @return [DeclarationPlan, Hash, nil] the child plan or nil
        def child_plan_for(plan, attr_name)
          return nil unless plan

          if plan.respond_to?(:child_plan)
            # DeclarationPlan object (Nokogiri/Oga)
            plan.child_plan(attr_name)
          elsif plan.respond_to?(:[])
            # Hash-based plan (Ox/REXML)
            plan[:children_plans]&.[](attr_name)
          end
        end

        # Build unordered child elements using prepared namespace declaration plan
        #
        # This is the shared implementation for all adapters. Adapters may override
        # if they need custom behavior.
        #
        # @param xml [Builder] the XML builder
        # @param element [Object] the model instance
        # @param plan [DeclarationPlan, Hash] the declaration plan
        # @param options [Hash] serialization options
        def build_unordered_children_with_plan(xml, element, plan, options)
          mapper_class = options[:mapper_class] || element.class
          xml_mapping = mapper_class.mappings_for(:xml)

          # Process child elements with their plans (INCLUDING raw_mapping for map all)
          mappings = xml_mapping.elements + [xml_mapping.raw_mapping].compact
          mappings.each do |element_rule|
            next if options[:except]&.include?(element_rule.to)

            # Handle custom methods
            if element_rule.custom_methods[:to]
              mapper_class.new.send(element_rule.custom_methods[:to], element,
                                    xml.parent, xml)
              next
            end

            attribute_def = attribute_definition_for(element, element_rule,
                                                     mapper_class: mapper_class)

            # For delegated attributes, attribute_def might be nil
            next unless attribute_def || element_rule.delegate

            value = attribute_value_for(element, element_rule)
            next unless element_rule.render?(value, element)

            # Get child's plan if available
            child_plan = child_plan_for(plan, element_rule.to)

            # Check if value is a Collection instance
            is_collection_instance = value.is_a?(Lutaml::Model::Collection)

            if value && (attribute_def&.type(register)&.<=(Lutaml::Model::Serialize) || is_collection_instance)
              handle_nested_elements_with_plan(
                xml,
                value,
                element_rule,
                attribute_def,
                child_plan,
                options,
                parent_plan: plan,
              )
            elsif element_rule.delegate && attribute_def.nil?
              # Handle non-model values (strings, etc.) for delegated attributes
              add_simple_value(xml, element_rule, value, nil, plan: plan,
                                                              mapping: xml_mapping, options: options)
            else
              add_simple_value(xml, element_rule, value, attribute_def,
                               plan: plan, mapping: xml_mapping, options: options)
            end
          end

          # Process content mapping
          process_content_mapping(element, xml_mapping.content_mapping,
                                  xml, mapper_class)
        end

        # Build ordered child elements using prepared namespace declaration plan
        #
        # This is the shared implementation for all adapters. Adapters may override
        # if they need custom behavior.
        #
        # @param xml [Builder] the XML builder
        # @param element [Object] the model instance
        # @param plan [DeclarationPlan, Hash] the declaration plan
        # @param options [Hash] serialization options
        def build_ordered_element_with_plan(xml, element, plan, options)
          mapper_class = options[:mapper_class] || element.class
          xml_mapping = mapper_class.mappings_for(:xml)

          index_hash = {}
          content = []

          element.element_order.each do |object|
            object_key = "#{object.name}-#{object.type}"
            index_hash[object_key] ||= -1
            curr_index = index_hash[object_key] += 1

            element_rule = xml_mapping.find_by_name(object.name,
                                                    type: object.type,
                                                    node_type: object.node_type,
                                                    namespace_uri: object.namespace_uri)
            next if element_rule.nil? || options[:except]&.include?(element_rule.to)

            # Handle custom methods
            if element_rule.custom_methods[:to]
              mapper_class.new.send(element_rule.custom_methods[:to], element,
                                    xml.parent, xml)
              next
            end

            # Get attribute definition and value (handle delegation)
            attribute_def, value = fetch_attribute_and_value(element,
                                                             element_rule, mapper_class)

            next if element_rule == xml_mapping.content_mapping && element_rule.cdata && object.text?

            if element_rule == xml_mapping.content_mapping
              process_ordered_content(element, xml_mapping, xml, curr_index,
                                      content)
            elsif !value.nil? || element_rule.render_nil?
              process_ordered_element(xml, element, element_rule, attribute_def,
                                      value, curr_index, plan, xml_mapping, options)
            end
          end

          add_ordered_content(xml, content) unless content.empty?
        end

        private

        # Fetch attribute definition and value, handling delegation
        #
        # @param element [Object] the model instance
        # @param element_rule [MappingRule] the mapping rule
        # @param mapper_class [Class] the mapper class
        # @return [Array<(Attribute, Object)>] attribute definition and value tuple
        def fetch_attribute_and_value(element, element_rule, mapper_class)
          attribute_def = nil
          value = nil

          if element_rule.delegate
            delegate_obj = element.send(element_rule.delegate)
            if delegate_obj.respond_to?(element_rule.to)
              attribute_def = delegate_obj.class.attributes[element_rule.to]
              value = delegate_obj.send(element_rule.to)
            end
          else
            attribute_def = attribute_definition_for(element, element_rule,
                                                     mapper_class: mapper_class)
            value = attribute_value_for(element, element_rule)
          end

          [attribute_def, value]
        end

        # Process content for ordered elements
        #
        # @param element [Object] the model instance
        # @param xml_mapping [Xml::Mapping] the XML mapping
        # @param xml [Builder] the XML builder
        # @param curr_index [Integer] current index in collection
        # @param content [Array] accumulated content strings
        def process_ordered_content(element, xml_mapping, xml, curr_index,
content)
          text = element.send(xml_mapping.content_mapping.to)
          text = text[curr_index] if text.is_a?(Array)

          if element.mixed?
            add_mixed_text(xml, text)
          else
            content << text
          end
        end

        # Process a single ordered element
        #
        # @param xml [Builder] the XML builder
        # @param element [Object] the model instance
        # @param element_rule [MappingRule] the mapping rule
        # @param attribute_def [Attribute, nil] the attribute definition
        # @param value [Object] the value
        # @param curr_index [Integer] current index in collection
        # @param plan [DeclarationPlan, Hash] the declaration plan
        # @param xml_mapping [Xml::Mapping] the XML mapping
        # @param options [Hash] serialization options
        def process_ordered_element(xml, element, element_rule, attribute_def,
                                    value, curr_index, plan, xml_mapping, options)
          # Handle collection values by index
          current_value = if attribute_def&.collection? && value.is_a?(Array)
                            value[curr_index]
                          elsif attribute_def&.collection? && value.is_a?(Lutaml::Model::Collection)
                            value.to_a[curr_index]
                          else
                            value
                          end

          # Get child's plan if available
          child_plan = child_plan_for(plan, element_rule.to)

          is_collection_instance = current_value.is_a?(Lutaml::Model::Collection)

          if current_value && (attribute_def&.type(register)&.<=(Lutaml::Model::Serialize) || is_collection_instance)
            handle_nested_elements_with_plan(
              xml,
              current_value,
              element_rule,
              attribute_def,
              child_plan,
              options,
              parent_plan: plan,
            )
          else
            # Apply transformations if attribute_def exists
            if attribute_def
              current_value = ExportTransformer.call(current_value,
                                                     element_rule, attribute_def, format: :xml)
            end

            # For mixed content, create elements directly
            if element.mixed? && !attribute_def&.raw?
              add_mixed_element(xml, element_rule, current_value, attribute_def,
                                plan: plan, mapping: xml_mapping)
            else
              add_simple_value(xml, element_rule, current_value,
                               attribute_def, plan: plan, mapping: xml_mapping, options: options)
            end
          end
        end

        # Add text for mixed content (can be overridden by adapters)
        #
        # @param xml [Builder] the XML builder
        # @param text [String] the text to add
        def add_mixed_text(xml, text)
          # Default implementation - adapters may override
          xml.add_text(xml, text) unless text.nil? || text.to_s.empty?
        end

        # Add element for mixed content (can be overridden by adapters)
        #
        # @param xml [Builder] the XML builder
        # @param element_rule [MappingRule] the element rule
        # @param value [Object] the value to add
        # @param attribute [Attribute, nil] the attribute definition
        # @param plan [DeclarationPlan, Hash, nil] the declaration plan
        # @param mapping [Xml::Mapping] the XML mapping
        def add_mixed_element(xml, element_rule, value, _attribute, _plan:,
_mapping:)
          # Default implementation - adapters may override
          xml.create_and_add_element(element_rule.name) do |child_element|
            child_element.text(value.to_s) unless ::Lutaml::Model::Utils.empty?(value)
          end
        end

        # Add accumulated content (can be overridden by adapters)
        #
        # @param xml [Builder] the XML builder
        # @param content [Array<String>] accumulated content strings
        def add_ordered_content(xml, content)
          # Default implementation - adapters may override
          xml.add_text(xml, content.join)
        end

        # Collect original namespace URIs from a model tree for namespace alias support.
        #
        # When parsing XML with alias URIs (e.g., "http://.../") against a namespace
        # class with canonical URI (e.g., "http://.../reqif.xsd"), the original alias
        # URI is stored on the model instance as @__xml_original_namespace_uri.
        # This method collects all such mappings from the model tree.
        #
        # @param model [Object] the model instance to walk
        # @param mapping [Xml::Mapping, nil] the mapping for the model
        # @return [Hash<String, String>] Mapping of canonical URI => original alias URI
        def collect_original_namespace_uris(model, mapping = nil)
          original_uris = {}
          return original_uris unless model

          collect_from_model(model, mapping, original_uris, Set.new)
          original_uris
        end

        # Recursively walk model tree to collect original namespace URIs
        def collect_from_model(model, mapping, original_uris, visited)
          return unless model.is_a?(::Lutaml::Model::Serialize)
          return if visited.include?(model.object_id)

          visited.add(model.object_id)

          # Check if this model has an original namespace URI
          if model.instance_variable_defined?(:@__xml_original_namespace_uri)
            original_uri = model.instance_variable_get(:@__xml_original_namespace_uri)
            if original_uri && !original_uri.empty?
              # Look up the model's namespace class
              ns_class = model.class.mappings_for(:xml)&.namespace_class
              if ns_class && ns_class.uri != original_uri
                # Only store if the canonical URI differs (it's an alias)
                original_uris[ns_class.uri] = original_uri
              end
            end
          end

          return unless mapping

          # Recurse into child Serializable attributes
          attributes = model.class.attributes
          mapping.elements.each do |elem_rule|
            attr_def = attributes[elem_rule.to]
            next unless attr_def

            child_type = attr_def.type(Lutaml::Model::Config.default_register)
            next unless child_type.respond_to?(:<) && child_type < ::Lutaml::Model::Serializable

            child_mapping = child_type.mappings_for(:xml)
            next unless child_mapping

            child_instance = model.public_send(elem_rule.to) if model.respond_to?(elem_rule.to)

            if child_instance.is_a?(Array) || child_instance.is_a?(::Lutaml::Model::Collection)
              instances = child_instance.is_a?(::Lutaml::Model::Collection) ? child_instance.collection : child_instance
              instances.each do |item|
                collect_from_model(item, child_mapping, original_uris, visited)
              end
            elsif child_instance
              collect_from_model(child_instance, child_mapping, original_uris,
                                 visited)
            end
          end
        end
      end
    end
  end
end
