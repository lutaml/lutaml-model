# frozen_string_literal: true

require_relative "../document"
require_relative "../declaration_handler"
require_relative "../doctype_extractor"
require_relative "../polymorphic_value_handler"

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
        include DeclarationHandler
        include PolymorphicValueHandler

        EMPTY_DOCUMENT_ERROR_MESSAGE = "Document has no root element. " \
                                       "The XML may be empty, contain only whitespace, " \
                                       "or consist only of an XML declaration."
        EMPTY_DOCUMENT_ERROR_TYPE = :invalid_format
        PARSE_ERROR_CLASS = nil

        OOXML_BOOLEAN_ELEMENTS = %w[
          b i strike bCs iCs smallCaps caps vanish noProof
          shadow emboss imprint keepNext keepLines outline
          tblHeader cantSplit contextualSpacing highlight
          rPr pPr trPr tcPr
        ].freeze

        # Class methods for element inspection
        # These are shared across all adapters

        def self.parse(xml, options = {})
          parse_encoding = encoding(xml, options)
          raw_xml = xml
          xml = normalize_xml_for_parse(xml)
          parsed = parse_with_moxml(xml, parse_encoding)
          root_element = parsed.root

          raise_empty_document_error if root_element.nil?

          @root = self::PARSED_ELEMENT_CLASS.new(root_element)
          new(@root, parse_encoding, **parse_document_options(raw_xml))
        end

        def self.normalize_xml_for_parse(xml)
          return xml unless xml.is_a?(String)
          return xml if xml.encoding == Encoding::UTF_8 && xml.valid_encoding?

          if xml.encoding == Encoding::ASCII_8BIT
            normalized_xml = xml.dup
            normalized_xml.force_encoding(Encoding::UTF_8)
            return normalized_xml if normalized_xml.valid_encoding?
          end

          xml.encode(Encoding::UTF_8,
                     invalid: :replace,
                     undef: :replace,
                     replace: "?")
        end

        def self.parse_with_moxml(xml, parse_encoding)
          parse_error_class = self::PARSE_ERROR_CLASS
          return self::MOXML_ADAPTER.parse(xml, encoding: parse_encoding) unless parse_error_class

          begin
            self::MOXML_ADAPTER.parse(xml, encoding: parse_encoding)
          rescue parse_error_class => e
            raise Lutaml::Model::InvalidFormatError.new(:xml, e.message)
          end
        end

        def self.parse_document_options(xml)
          {
            doctype: extract_doctype_from_xml(xml),
            xml_declaration: DeclarationHandler.extract_xml_declaration(xml),
          }
        end

        def self.raise_empty_document_error
          message = self::EMPTY_DOCUMENT_ERROR_MESSAGE

          case self::EMPTY_DOCUMENT_ERROR_TYPE
          when :parse_exception
            raise REXML::ParseException.new(message)
          else
            raise Lutaml::Model::InvalidFormatError.new(:xml, message)
          end
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
          elsif @encoding
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
          return false unless element.respond_to?(:element_order)

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
          if element.respond_to?(:attributes_each_value)
            element.attributes_each_value(&)
          else
            element.attributes.each_value(&)
          end
        end

        def schema_location_attribute?(attr)
          attr_name = if attr.respond_to?(:unprefixed_name)
                        attr.unprefixed_name
                      else
                        attr.name
                      end
          attr_name == "schemaLocation"
        end

        def attribute_namespace_prefix(attr)
          if attr.respond_to?(:namespace_prefix)
            attr.namespace_prefix
          else
            attr.namespace&.prefix
          end
        end

        def attribute_hash_name(attr)
          if attr.respond_to?(:namespaced_name)
            attr.namespaced_name
          else
            self.class.namespaced_attr_name(attr)
          end
        end

        public

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

        def to_xml(options = {})
          # Accept xml_declaration from options if present (for model serialization)
          @xml_declaration = options[:xml_declaration] if options[:xml_declaration]

          encoding = determine_encoding(options)
          builder_options = {}
          builder_options[:encoding] = encoding if encoding

          builder = self.class::BUILDER_CLASS.build(builder_options) do |xml|
            if root.is_a?(self.class::PARSED_ELEMENT_CLASS)
              root.build_xml(xml)
            else
              build_serializable_xml(xml, options)
            end
          end

          finalize_adapter_xml(builder.to_xml, encoding, options)
        end

        def build_serializable_xml(xml, options)
          original_model = nil
          xml_element = transformable_xml_element(options) do |model|
            original_model = model
          end

          if xml_element
            render_xml_element(xml, xml_element, original_model, options)
          else
            render_legacy_model(xml, options)
          end
        end

        def transformable_xml_element(options)
          return root if root.is_a?(Lutaml::Xml::DataModel::XmlElement)

          mapper_class = options[:mapper_class] || root.class
          xml_mapping = mapper_class.mappings_for(:xml)

          return nil if xml_mapping.raw_mapping&.custom_methods&.[](:to)

          yield(root)
          mapper_class.transformation_for(:xml, register).transform(root,
                                                                    options)
        end

        def render_xml_element(xml, xml_element, original_model, options)
          mapper_class = options[:mapper_class] || xml_element.class
          mapping = mapper_class.mappings_for(:xml)
          plan = declaration_plan_for(
            xml_element,
            mapping,
            options_with_original_namespace_data(options, original_model,
                                                 xml_element),
            mapper_class,
          )

          render_options = options.merge(is_root_element: true)
          render_options[:original_model] = original_model if original_model
          build_xml_element_with_plan(xml, xml_element, plan, render_options)
        end

        def render_legacy_model(xml, options)
          mapper_class = options[:mapper_class] || root.class
          xml_mapping = mapper_class.mappings_for(:xml)
          plan = declaration_plan_for(root, xml_mapping, options, mapper_class)

          build_element_with_plan(xml, root, plan, options)
        end

        def declaration_plan_for(element, mapping, options, mapper_class)
          needs = NamespaceCollector.new(register).collect(
            element, mapping, mapper_class: mapper_class
          )
          DeclarationPlanner.new(register).plan(element, mapping, needs,
                                                options: options)
        end

        def options_with_original_namespace_data(options, original_model,
    xml_element)
          original_ns_uris = {}
          stored_plan = nil

          if original_model
            mapping_for_original = options[:mapper_class]&.mappings_for(:xml) ||
              original_model.class.mappings_for(:xml)
            original_ns_uris = collect_original_namespace_uris(
              original_model, mapping_for_original
            )
            if original_model.is_a?(Lutaml::Model::Serialize)
              stored_plan = original_model.import_declaration_plan
            end
          elsif xml_element.is_a?(Lutaml::Xml::DataModel::XmlElement)
            original_ns_uri = xml_element.original_namespace_uri
            if original_ns_uri
              mapper_class = options[:mapper_class] || xml_element.class
              xml_mapping = begin
                mapper_class.mappings_for(:xml)
              rescue StandardError
                nil
              end
              if xml_mapping&.namespace_class
                canonical_uri = xml_mapping.namespace_class.uri
                original_ns_uris[canonical_uri] = original_ns_uri if canonical_uri != original_ns_uri
              end
            end
          end

          options_with_original_ns = options.merge(
            __original_namespace_uris: original_ns_uris,
          )
          if stored_plan
            options_with_original_ns[:stored_xml_declaration_plan] =
              stored_plan
          end
          options_with_original_ns
        end

        def finalize_adapter_xml(xml_data, encoding, options)
          result = ""
          if (options[:encoding] && !options[:encoding].nil?) ||
              should_include_declaration?(options)
            result += generate_declaration(options)
          end

          doctype_to_use = options[:doctype] || @doctype
          if doctype_to_use && !options[:omit_doctype]
            result += generate_doctype_declaration(doctype_to_use)
          end

          result += xml_data
          if encoding && result.encoding.to_s.upcase != encoding.to_s.upcase
            result = result.encode(encoding)
          end
          if options[:fix_boolean_elements]
            result = fix_ooxml_format(result)
          end
          result
        end

        def fix_ooxml_format(xml)
          bool_elem_pattern = OOXML_BOOLEAN_ELEMENTS.join("|")

          xml = xml.gsub(
            /<([a-zA-Z][a-zA-Z0-9]*):(#{bool_elem_pattern})([^>]*)\/>/,
          ) do
            prefix = $1
            element_name = $2
            attrs = $3
            fixed_attrs = attrs.sub(/\s+w:val="(?:true|1)"/, "")
            fixed_attrs == attrs ? $& : "<#{prefix}:#{element_name}#{fixed_attrs}/>"
          end

          xml = xml.gsub(
            /<([a-zA-Z][a-zA-Z0-9]*):(#{bool_elem_pattern})([^>]*)><\/\1:\2>/,
          ) do
            prefix = $1
            element_name = $2
            attrs = $3
            fixed_attrs = attrs.sub(/\s+w:val="(?:true|1)"/, "")
            fixed_attrs == attrs ? $& : "<#{prefix}:#{element_name}#{fixed_attrs}/>"
          end

          xml = xml.gsub(
            /<([a-zA-Z][a-zA-Z0-9]*):(#{bool_elem_pattern})([^>]*)>(?:true|1)<\/\1:\2>/,
          ) do
            prefix = $1
            element_name = $2
            attrs = $3.sub(/\s+w:val="(?:true|1)"/, "")
            "<#{prefix}:#{element_name}#{attrs}/>"
          end

          xml = xml.gsub(
            /<([a-zA-Z][a-zA-Z0-9]*):(#{bool_elem_pattern})>(?:true|1)<\/\1:\2>/,
          ) { "<#{$1}:#{$2}/>" }

          xml.gsub(/\bw:xml:space=/, "xml:space=")
        end

        def build_xml_element_with_plan(builder, xml_element, plan,
    options = {})
          build_plan_node(builder, xml_element, plan.root_node, plan: plan,
                                                                options: options)
        end

        private

        def text_content_for_xml(value)
          ::Moxml::Adapter::Base.preprocess_entities(value.to_s)
        end

        def build_plan_node(xml, xml_element, element_node, plan: nil,
    options: {}, previous_sibling_had_xmlns_blank: false)
          qualified_name = element_node.qualified_name
          attributes = {}

          original_ns_uris = plan&.original_namespace_uris || {}
          element_node.hoisted_declarations.each do |key, uri|
            next if uri == "http://www.w3.org/XML/1998/namespace"

            effective_uri = if self.class.fpi?(uri)
                              self.class.fpi_to_urn(uri)
                            else
                              original_ns_uris[uri] || uri
                            end

            xmlns_name = key ? "xmlns:#{key}" : "xmlns"
            attributes[xmlns_name] = effective_uri
          end

          xml_element.attributes.each_with_index do |xml_attr, idx|
            attr_node = element_node.attribute_nodes[idx]
            attributes[attr_node.qualified_name] = xml_attr.value.to_s
          end

          if xml_element.respond_to?(:xsi_nil) && xml_element.xsi_nil
            attributes["xsi:nil"] = "true"
          end

          attributes.merge!(element_node.schema_location_attr) if element_node.schema_location_attr
          needs_xmlns_blank = element_node.needs_xmlns_blank &&
            (options[:pretty] ? !previous_sibling_had_xmlns_blank : true)
          attributes["xmlns"] = "" if needs_xmlns_blank

          xml.create_and_add_element(qualified_name, attributes: attributes) do
            if xml_element.respond_to?(:raw_content)
              raw_content = xml_element.raw_content
              if raw_content && !raw_content.to_s.empty?
                xml.add_xml_fragment(xml, raw_content.to_s)
                return
              end
            end

            child_element_index = 0
            previous_child_had_xmlns_blank = false
            xml_element.children.each do |xml_child|
              if xml_child.is_a?(Lutaml::Xml::DataModel::XmlElement)
                child_node = element_node.element_nodes[child_element_index]
                child_element_index += 1

                build_plan_node(
                  xml,
                  xml_child,
                  child_node,
                  plan: plan,
                  options: options,
                  previous_sibling_had_xmlns_blank: previous_child_had_xmlns_blank,
                )
                previous_child_had_xmlns_blank ||= child_node.needs_xmlns_blank
              elsif xml_child.is_a?(String)
                xml.text(text_content_for_xml(xml_child))
              end
            end

            if xml_element.text_content
              if xml_element.cdata
                xml.cdata(xml_element.text_content.to_s)
              else
                xml.text(text_content_for_xml(xml_element.text_content))
              end
            end
          end
        end

        public

        # Build element using prepared namespace declaration plan
        #
        # @param xml [Builder] the XML builder
        # @param element [Object] the model instance
        # @param plan [Hash] the declaration plan from DeclarationPlanner
        # @param options [Hash] serialization options
        def build_element_with_plan(xml, element, plan, options = {})
          plan ||= DeclarationPlan.empty
          mapper_class = options[:mapper_class] || element.class

          unless mapper_class.is_a?(Class) &&
              mapper_class.include?(Lutaml::Model::Serialize)
            tag_name = options[:tag_name] || "element"
            xml.create_and_add_element(tag_name) do |inner_xml|
              inner_xml.text(text_content_for_xml(element))
            end
            return xml
          end

          xml_mapping = mapper_class.mappings_for(:xml)
          return xml unless xml_mapping

          # TYPE-ONLY MODELS: No element wrapper, serialize children directly
          # BUT if we have a tag_name in options, that means parent wants a wrapper
          if xml_mapping.no_element?
            # If parent provided a tag_name, create that wrapper first
            if options[:tag_name]
              xml.create_and_add_element(options[:tag_name]) do |inner_xml|
                # Serialize type-only model's children inside parent's wrapper
                xml_mapping.elements.each do |element_rule|
                  next if options[:except]&.include?(element_rule.to)

                  attribute_def = mapper_class.attributes[element_rule.to]
                  next unless attribute_def

                  value = element.send(element_rule.to)
                  next unless element_rule.render?(value, element)

                  # For type-only models, children plans may not be available
                  # Serialize children directly
                  if value && attribute_def.type(register)&.<=(Lutaml::Model::Serialize)
                    # Nested model - recursively build it
                    child_plan = plan.child_plan(element_rule.to) || DeclarationPlan.empty
                    build_element_with_plan(
                      inner_xml,
                      value,
                      child_plan,
                      { mapper_class: attribute_def.type(register),
                        tag_name: element_rule.name },
                    )
                  else
                    # Simple value - create element directly
                    inner_xml.create_and_add_element(element_rule.name) do
                      add_value(inner_xml, value, attribute_def,
                                cdata: element_rule.cdata)
                    end
                  end
                end
              end
            else
              # No wrapper at all - serialize children directly (for root-level type-only)
              xml_mapping.elements.each do |element_rule|
                next if options[:except]&.include?(element_rule.to)

                attribute_def = mapper_class.attributes[element_rule.to]
                next unless attribute_def

                value = element.send(element_rule.to)
                next unless element_rule.render?(value, element)

                child_plan = plan.child_plan(element_rule.to)

                if value && attribute_def.type(register)&.<=(Lutaml::Model::Serialize)
                  handle_nested_elements_with_plan(
                    xml,
                    value,
                    element_rule,
                    attribute_def,
                    child_plan,
                    options,
                  )
                else
                  add_simple_value(xml, element_rule, value, attribute_def,
                                   plan: plan, mapping: xml_mapping, options: options)
                end
              end
            end
            return xml
          end

          # Use xmlns declarations from plan
          attributes = {}

          # Apply namespace declarations from plan using extracted module
          attributes.merge!(NamespaceDeclarationBuilder.build_xmlns_attributes(plan))

          # Collect attribute custom methods to call after element creation
          attribute_custom_methods = []

          # Add regular attributes (non-xmlns)
          xml_mapping.attributes.each do |attribute_rule|
            next if options[:except]&.include?(attribute_rule.to)

            # Collect custom methods for later execution (after element is created)
            if attribute_rule.custom_methods[:to]
              attribute_custom_methods << attribute_rule
              next
            end

            mapping_rule_name = if attribute_rule.multiple_mappings?
                                  attribute_rule.name.first
                                else
                                  attribute_rule.name
                                end

            attr = attribute_definition_for(element, attribute_rule,
                                            mapper_class: mapper_class)
            value = attribute_rule.to_value_for(element)

            # Handle as_list and delimiter BEFORE serialization for array values
            # These features convert arrays to delimited strings before serialization
            if value.is_a?(Array)
              if attribute_rule.as_list && attribute_rule.as_list[:export]
                value = attribute_rule.as_list[:export].call(value)
              elsif attribute_rule.delimiter
                value = value.join(attribute_rule.delimiter)
              end
            end

            value = attr.serialize(value, :xml, register) if attr
            value = ExportTransformer.call(value, attribute_rule, attr,
                                           format: :xml)

            if render_element?(attribute_rule, element, value)
              # Resolve attribute namespace using extracted module
              ns_info = AttributeNamespaceResolver.resolve(
                rule: attribute_rule,
                attribute: attr,
                plan: plan,
                mapper_class: mapper_class,
                register: register,
              )

              # Build qualified attribute name based on W3C semantics
              attr_name = AttributeNamespaceResolver.build_qualified_name(
                ns_info,
                mapping_rule_name,
                attribute_rule,
              )
              attributes[attr_name] = value ? value.to_s : value

              # Add local xmlns declaration if needed
              if ns_info[:needs_local_declaration]
                attributes[ns_info[:local_xmlns_attr]] =
                  ns_info[:local_xmlns_uri]
              end
            end
          end

          # Add schema_location attribute from ElementNode if present
          # This is for the plan-based path where schema_location_attr is computed during planning
          attributes.merge!(plan.root_node.schema_location_attr) if plan&.root_node&.schema_location_attr

          # Determine prefix from plan using extracted module
          prefix_info = ElementPrefixResolver.resolve(mapping: xml_mapping,
                                                      plan: plan)
          prefix = prefix_info[:prefix]
          ns_decl = if xml_mapping.namespace_class
                      plan.namespace_for_class(xml_mapping.namespace_class)
                    end

          # Check if element's own namespace needs local declaration (out of scope)
          if ns_decl&.local_on_use?
            xmlns_attr = prefix ? "xmlns:#{prefix}" : "xmlns"
            attributes[xmlns_attr] = ns_decl.uri
          end

          # W3C COMPLIANCE: Detect if element needs xmlns="" using extracted module
          if BlankNamespaceHandler.needs_xmlns_blank?(mapping: xml_mapping,
                                                      options: options)
            attributes["xmlns"] = ""
          end

          # Native type inheritance fix: handle local_on_use xmlns="" even if parents uses default format
          xmlns_prefix = nil
          xmlns_ns = nil
          if xml_mapping&.namespace_class && plan
            xmlns_ns = plan.namespace_for_class(xml_mapping.namespace_class)
            xmlns_prefix = xmlns_ns&.prefix
          end
          if xmlns_ns&.local_on_use? && !xml_mapping.namespace_uri
            attributes["xmlns:#{xmlns_prefix}"] =
              xmlns_ns&.uri || xml_mapping.namespace_uri
          end

          tag_name = options[:tag_name] || xml_mapping.root_element
          return if options[:except]&.include?(tag_name)

          # Track if THIS element uses default namespace format
          # Children will need this info to know if they should add xmlns=""
          this_element_uses_default_ns = xml_mapping.namespace_class &&
            plan.namespace_for_class(xml_mapping.namespace_class)&.default_format?

          # Get element_form_default from this element's namespace for children
          parent_element_form_default = xml_mapping.namespace_class&.element_form_default

          xml.create_and_add_element(tag_name, attributes: attributes.compact,
                                               prefix: prefix) do |inner_xml|
            # Call attribute custom methods now that element is created
            attribute_custom_methods.each do |attribute_rule|
              mapper_class.new.send(attribute_rule.custom_methods[:to],
                                    element, inner_xml.parent, inner_xml)
            end

            if ordered?(element, options.merge(mapper_class: mapper_class))
              build_ordered_element_with_plan(inner_xml, element, plan,
                                              options.merge(
                                                mapper_class: mapper_class,
                                                parent_prefix: prefix,
                                                parent_uses_default_ns: this_element_uses_default_ns,
                                                parent_element_form_default: parent_element_form_default,
                                                parent_ns_decl: ns_decl,
                                              ))
            else
              build_unordered_children_with_plan(inner_xml, element, plan,
                                                 options.merge(
                                                   mapper_class: mapper_class,
                                                   parent_prefix: prefix,
                                                   parent_uses_default_ns: this_element_uses_default_ns,
                                                   parent_element_form_default: parent_element_form_default,
                                                   parent_ns_decl: ns_decl,
                                                 ))
            end
          end
        end

        # Build XML from XmlDataModel::XmlElement structure
        #
        # @param xml [Builder] XML builder
        # @param element [XmlDataModel::XmlElement] element to build
        # @param parent_uses_default_ns [Boolean] parent uses default namespace format
        # @param parent_element_form_default [Symbol] parent's element_form_default
        # @param parent_namespace_class [Class] parent's namespace class
        # @param plan [DeclarationPlan, nil] optional declaration plan for xmlns=""
        # @param xml_mapping [Xml::Mapping] optional mapping for namespace resolution
        def build_xml_element(xml, element, parent_uses_default_ns: false,
    parent_element_form_default: nil, parent_namespace_class: nil, plan: nil, xml_mapping: nil)
          # Prepare attributes hash
          attributes = {}

          # Get element's namespace class
          element_ns_class = element.namespace_class
          attribute_form_default = element_ns_class&.attribute_form_default || :unqualified
          element_prefix = element_ns_class&.prefix_default

          # Get element_form_default for children
          this_element_form_default = element_ns_class&.element_form_default || :unqualified

          # Add regular attributes
          element.attributes.each do |attr|
            # Determine attribute name with namespace consideration
            attr_name = if attr.namespace_class
                          # Check if attribute is in SAME namespace as element
                          if attr.namespace_class == element_ns_class && attribute_form_default == :unqualified
                            # Same namespace + unqualified → NO prefix (W3C rule)
                            attr.name
                          else
                            # Different namespace OR qualified → use prefix
                            attr_prefix = attr.namespace_class.prefix_default
                            attr_prefix ? "#{attr_prefix}:#{attr.name}" : attr.name
                          end
                        elsif attribute_form_default == :qualified && element_prefix
                          # Attribute inherits element's namespace when qualified
                          "#{element_prefix}:#{attr.name}"
                        else
                          # Unqualified attribute
                          attr.name
                        end
            # Ensure attribute value is a string
            attributes[attr_name] = attr.value.to_s
          end

          # Determine element name with namespace prefix
          tag_name = element.name

          # Priority 2.5: Child namespace different from parent's default namespace
          # MUST use prefix format to distinguish from parent
          child_needs_prefix = if element_ns_class && parent_namespace_class &&
              element_ns_class != parent_namespace_class && parent_uses_default_ns
                                 element_prefix # Use child's prefix
                               end

          # FIX: Read prefix from plan if available, otherwise use fallback logic
          prefix = if child_needs_prefix
                     # Priority 2.5 takes precedence
                     child_needs_prefix
                   elsif plan && element_ns_class
                     # Read format decision from DeclarationPlan
                     ns_info = ElementPrefixResolver.resolve(
                       mapping: xml_mapping,
                       plan: plan,
                     )
                     ns_info[:prefix]
                   elsif element_ns_class && element_prefix
                     # Fallback: Element has explicit prefix_default - use prefix format
                     element_prefix
                   end

          # Track if THIS element uses default namespace format for children
          this_element_uses_default_ns = false

          # Add namespace declaration if element has namespace
          if element.namespace_class
            ns_uri = element.namespace_class.uri

            # Check if namespace is already declared by parent (hoisting optimization)
            # This works for BOTH default and prefix format parents
            ns_already_declared = parent_namespace_class && parent_namespace_class.uri == ns_uri

            if prefix && !ns_already_declared
              attributes["xmlns:#{prefix}"] = ns_uri
              # W3C Compliance: xmlns="" only needed for blank namespace children
              # Prefixed children are already in different namespace from parent's default
            elsif !prefix && !ns_already_declared
              attributes["xmlns"] = ns_uri
              this_element_uses_default_ns = true
            end
          elsif plan && DeclarationPlanQuery.element_needs_xmlns_blank?(plan,
                                                                        element)
            # W3C Compliance: Element has no namespace (blank namespace)
            # Check if DeclarationPlan says this element needs xmlns=""
            # The planner already determined this based on W3C semantics during planning phase
            attributes["xmlns"] = ""
          elsif !plan
            # Fallback logic when no plan is available
            # Check if should inherit parent's namespace based on element_form_default
            if parent_uses_default_ns
              # Parent uses default namespace format
              if parent_element_form_default == :qualified
                # Child should INHERIT parent's namespace - no xmlns="" needed
                # The child is in same namespace as parent (qualified)
              else
                # Parent's element_form_default is :unqualified - child in blank namespace
                # Add xmlns="" to explicitly opt out of parent's default namespace
                attributes["xmlns"] = ""
              end
            end
          end

          # Check if element was created from nil value with render_nil option
          # Add xsi:nil="true" attribute for W3C compliance
          if element.respond_to?(:xsi_nil) && element.xsi_nil
            attributes["xsi:nil"] = true
          end

          # Create element
          xml.create_and_add_element(tag_name, attributes: attributes,
                                               prefix: prefix) do |inner_xml|
            # Handle raw content (map_all directive)
            has_raw_content = false
            if element.respond_to?(:raw_content)
              raw_content = element.raw_content
              if raw_content && !raw_content.to_s.empty?
                inner_xml.add_xml_fragment(inner_xml, raw_content.to_s)
                has_raw_content = true
              end
            end

            # Skip text content and children if we have raw content
            unless has_raw_content
              # Add text content if present
              if element.text_content
                if element.cdata
                  inner_xml.cdata(element.text_content.to_s)
                else
                  inner_xml.text(text_content_for_xml(element.text_content))
                end
              end

              # Recursively build child elements, passing namespace context and plan
              element.children.each do |child|
                if child.is_a?(Lutaml::Xml::DataModel::XmlElement)
                  build_xml_element(inner_xml, child,
                                    parent_uses_default_ns: this_element_uses_default_ns,
                                    parent_element_form_default: this_element_form_default,
                                    parent_namespace_class: element_ns_class,
                                    plan: plan,
                                    xml_mapping: xml_mapping)
                elsif child.is_a?(String)
                  inner_xml.text(text_content_for_xml(child))
                end
              end
            end
          end
        end

        def handle_nested_elements_with_plan(xml, value, rule, attribute, plan,
    options, parent_plan: nil)
          element_options = options.merge(
            rule: rule,
            attribute: attribute,
            tag_name: rule.name,
            mapper_class: attribute.type(register), # Override with child's type
          )

          # Handle Collection instances
          if value.is_a?(Lutaml::Model::Collection)
            items = value.collection
            attr_type = attribute.type(register)

            if attr_type <= Lutaml::Model::Type::Value
              # Simple types - use add_simple_value for each item
              items.each do |val|
                xml_mapping = options[:mapper_class]&.mappings_for(:xml)
                add_simple_value(xml, rule, val, attribute, plan: parent_plan,
                                                            mapping: xml_mapping, options: options)
              end
            else
              # Model types - build elements with plans
              items.each do |val|
                # For polymorphic collections, use each item's actual class
                item_mapper_class = if polymorphic_value?(attribute, val)
                                      val.class
                                    else
                                      attribute.type(register)
                                    end

                # CRITICAL: Transform model to XmlElement, then collect and plan
                item_mapping = item_mapper_class.mappings_for(:xml)
                if item_mapping
                  # Transform model to XmlElement tree
                  transformation = item_mapper_class.transformation_for(:xml,
                                                                        register)
                  xml_element = transformation.transform(val, options)

                  # Collect namespace needs from XmlElement tree
                  collector = NamespaceCollector.new(register)
                  item_needs = collector.collect(xml_element, item_mapping,
                                                 mapper_class: item_mapper_class)

                  # Plan with XmlElement tree (not model instance)
                  planner = DeclarationPlanner.new(register)
                  item_plan = planner.plan(xml_element, item_mapping,
                                           item_needs, parent_plan: parent_plan, options: options)
                else
                  item_plan = plan
                end

                item_options = element_options.merge(mapper_class: item_mapper_class)
                build_element_with_plan(xml, val, item_plan, item_options)
              end
            end
            return
          end

          case value
          when Array
            value.each do |val|
              # For polymorphic arrays, use each item's actual class
              item_mapper_class = if polymorphic_value?(attribute, val)
                                    val.class
                                  else
                                    attribute.type(register)
                                  end

              # CRITICAL: Transform model to XmlElement, then collect and plan
              item_mapping = item_mapper_class.mappings_for(:xml)
              if item_mapping
                # Transform model to XmlElement tree
                transformation = item_mapper_class.transformation_for(:xml,
                                                                      register)
                xml_element = transformation.transform(val, options)

                # Collect namespace needs from XmlElement tree
                collector = NamespaceCollector.new(register)
                item_needs = collector.collect(xml_element, item_mapping,
                                               mapper_class: item_mapper_class)

                # Plan with XmlElement tree (not model instance)
                planner = DeclarationPlanner.new(register)
                item_plan = planner.plan(xml_element, item_mapping, item_needs,
                                         parent_plan: parent_plan, options: options)
              else
                item_plan = plan
              end

              item_options = element_options.merge(mapper_class: item_mapper_class)
              if item_plan
                build_element_with_plan(xml, val, item_plan, item_options)
              else
                build_element(xml, val, item_options)
              end
            end
          else
            build_element_with_plan(xml, value, plan, element_options)
          end
        end

        # Add simple (non-model) values to XML
        def add_simple_value(xml, rule, value, attribute, plan: nil,
    mapping: nil, options: {})
          value = rule.render_value_for(value) if rule

          if value.is_a?(Array)
            if value.empty?
              if rule.render_empty?
                if rule.render_empty_as_nil?
                  xml.create_and_add_element(rule.name,
                                             attributes: { "xsi:nil" => true },
                                             prefix: nil)
                else
                  xml.create_and_add_element(rule.name,
                                             attributes: nil,
                                             prefix: nil)
                end
              end
              return
            end

            value.each do |val|
              add_simple_value(xml, rule, val, attribute, plan: plan,
                                                          mapping: mapping, options: options)
            end
            return
          end

          resolver = NamespaceResolver.new(register)

          # Extract parent_uses_default_ns from options or calculate it
          parent_uses_default_ns = options[:parent_uses_default_ns]
          if parent_uses_default_ns.nil?
            parent_uses_default_ns = if mapping&.namespace_class && plan
                                       DeclarationPlanQuery.declared_at_root_default_format?(plan,
                                                                                             mapping.namespace_class)
                                     else
                                       false
                                     end
          end

          # Resolve namespace using the resolver
          ns_result = resolver.resolve_for_element(rule, attribute, mapping,
                                                   plan, options)
          resolved_prefix = ns_result[:prefix]
          type_ns_info = ns_result[:ns_info]

          # CRITICAL FIX: Type namespace format inheritance for namespace_scope
          # When a type has namespace_class and that namespace is in the stored plan,
          # inherit the format from the stored plan (preserves input format)
          type_ns_class = if attribute && !rule.namespace_set?
                            type_class = attribute.type(register)
                            type_class.namespace_class if type_class.is_a?(Class) && type_class <= Lutaml::Model::Type::Value
                          end

          format_from_stored_plan = false
          false # Will be set below if needed

          if type_ns_class
            # Check BOTH the current plan (programmatic) and stored plan (round-trip)
            check_plan = plan || options[:stored_xml_declaration_plan]
            if check_plan
              stored_ns_decl = check_plan.namespaces.values.find do |decl|
                decl.uri == type_ns_class.uri
              end
              if stored_ns_decl
                # Namespace in plan - inherit its format
                # CRITICAL: local_on_use namespaces MUST use prefix format
                # (can't use default format - parent already using default)
                resolved_prefix = if stored_ns_decl.local_on_use? || stored_ns_decl.prefix_format?
                                    stored_ns_decl.prefix
                                  end
                format_from_stored_plan = true # Don't let subsequent logic override this
                false # Using plan namespace format, no xmlns="" needed
              end
            end
          end

          # BUG FIX #49: Check if child element is in same namespace as parent
          # If yes, inherit parent's format (default vs prefix)

          # Get parent's namespace URI
          parent_ns_class = options[:parent_namespace_class]
          parent_ns_decl = options[:parent_ns_decl]
          parent_ns_uri = parent_ns_class&.uri

          # Get child's resolved namespace URI
          child_ns_uri = ns_result[:uri]

          # CRITICAL FIX FOR NATIVE TYPE NAMESPACE INHERITANCE:
          # Elements without explicit namespace declaration should NOT inherit
          # parent's prefix format. They should be in blank namespace.
          #
          # BUT: Skip this logic if we already determined format from stored plan
          unless format_from_stored_plan
            # Check if this is a native type without explicit namespace:
            # 1. No namespace directive on the mapping rule
            # 2. Attribute type doesn't have namespace_class (native type like :string)
            element_has_no_explicit_ns = !rule.namespace_set?
            type_class = attribute&.type(register)
            type_has_no_ns = !(type_class.is_a?(Class) && type_class <= Lutaml::Model::Type::Value) ||
              !type_class&.namespace_class

            # If native type with no explicit namespace, DON'T inherit parent's prefix
            if element_has_no_explicit_ns && type_has_no_ns
              # Native type - force blank namespace (no prefix)
              resolved_prefix = nil
              # Check if parent uses default format - if so, need xmlns="" to opt out
              parent_ns_decl&.default_format?
            elsif parent_ns_class && parent_ns_decl &&
                child_ns_uri && parent_ns_uri &&
                child_ns_uri == parent_ns_uri
              # Same namespace URI - inherit parent's format
              resolved_prefix = if parent_ns_decl.prefix_format?
                                  parent_ns_decl.prefix
                                end
              # No blank xmlns needed when inheriting
              false
            else
              # Different namespace or no parent context - use standard resolution
              resolved_prefix = ns_result[:prefix]
              ns_result[:blank_xmlns]
            end
          end

          # Prepare attributes for element creation
          attributes = {}

          # W3C COMPLIANCE: Use resolver to determine xmlns="" requirement
          if resolver.xmlns_blank_required?(ns_result, parent_uses_default_ns)
            attributes["xmlns"] = ""
          end

          # Check if this namespace needs local declaration (out of scope)
          if resolved_prefix && plan&.namespaces
            ns_entry = plan.namespaces.values.find do |ns_decl|
              ns_decl.ns_object.prefix_default == resolved_prefix ||
                (type_ns_info && type_ns_info[:uri] && ns_decl.ns_object.uri == type_ns_info[:uri])
            end

            if ns_entry&.local_on_use?
              xmlns_attr = resolved_prefix ? "xmlns:#{resolved_prefix}" : "xmlns"
              attributes[xmlns_attr] = ns_entry.ns_object.uri
            end
          end

          if value.nil?
            if rule.render_nil_as_blank? || rule.render_nil_as_empty?
              xml.create_and_add_element(rule.name,
                                         attributes: attributes.empty? ? nil : attributes,
                                         prefix: resolved_prefix)
            else
              xml.create_and_add_element(rule.name,
                                         attributes: attributes.merge({ "xsi:nil" => true }),
                                         prefix: resolved_prefix)
            end
          elsif ::Lutaml::Model::Utils.uninitialized?(value)
            nil
          elsif ::Lutaml::Model::Utils.empty?(value)
            xml.create_and_add_element(rule.name,
                                       attributes: attributes.empty? ? nil : attributes,
                                       prefix: resolved_prefix)
          elsif rule.raw_mapping?
            xml.add_xml_fragment(xml, value)
          elsif value.is_a?(::Hash) && attribute&.type(register) == Lutaml::Model::Type::Hash
            # Check if value is Hash type that needs wrapper
            xml.create_and_add_element(rule.name,
                                       attributes: attributes.empty? ? nil : attributes,
                                       prefix: resolved_prefix) do
              value.each do |key, val|
                xml.create_and_add_element(key.to_s) do
                  xml.add_text(xml, val.to_s)
                end
              end
            end
          else
            xml.create_and_add_element(rule.name,
                                       attributes: attributes.empty? ? nil : attributes,
                                       prefix: resolved_prefix) do
              add_value(xml, value, attribute, cdata: rule.cdata)
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

        # Add text or CDATA content to a moxml element.
        # Nokogiri overrides add_text_nodes for entity reference preservation.
        def add_content_node(element, text, doc, cdata: false)
          if cdata
            element.add_child(doc.create_cdata(text.to_s))
          else
            add_text_nodes(element, text.to_s, doc)
          end
        end

        # Create text node(s) for element content.
        # Default: single text node. Nokogiri overrides to split entity references.
        def add_text_nodes(element, text, doc)
          element.add_child(doc.create_text(text))
        end

        # Apply XML attributes from XmlElement to a moxml element,
        # filtering xmlns attributes that are already declared via hoisted_declarations.
        def apply_plan_attributes(xml_element, element_node, element)
          xml_element.attributes.each_with_index do |xml_attr, idx|
            attr_name_str = xml_attr.name.to_s
            if attr_name_str.start_with?("xmlns")
              apply_xmlns_attribute(attr_name_str, xml_attr.value.to_s,
                                    element_node, element)
              next
            end

            attr_node = element_node.attribute_nodes[idx]
            element[attr_node.qualified_name] = xml_attr.value.to_s
          end
        end

        def apply_xmlns_attribute(attr_name_str, value, element_node, element)
          if attr_name_str.include?(":")
            prefix = attr_name_str.split(":", 2).last
            unless element_node.hoisted_declarations.key?(prefix)
              element.add_namespace(prefix, value)
            end
          elsif attr_name_str == "xmlns"
            unless element_node.hoisted_declarations.key?(nil)
              element.add_namespace(nil, value)
            end
          end
        end

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
          if model.respond_to?(:original_namespace_uri) && model.original_namespace_uri
            original_uri = model.original_namespace_uri
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
