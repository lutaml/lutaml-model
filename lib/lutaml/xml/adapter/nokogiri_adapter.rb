require "nokogiri"
require_relative "base_adapter"

module Lutaml
  module Xml
    module Adapter
      class NokogiriAdapter < BaseAdapter
        def self.parse(xml, options = {})
          parsed = ::Nokogiri::XML(xml, nil, encoding(xml, options))

          # Validate that we have a root element
          if parsed.root.nil?
            raise Lutaml::Model::InvalidFormatError.new(
              :xml,
              "Document has no root element. " \
              "The XML may be empty, contain only whitespace, " \
              "or consist only of an XML declaration.",
            )
          end

          # Extract DOCTYPE information for model serialization
          doctype_info = if parsed.internal_subset
                           {
                             name: parsed.internal_subset.name,
                             public_id: parsed.internal_subset.external_id,
                             system_id: parsed.internal_subset.system_id,
                           }
                         end

          # Extract XML declaration for Issue #1: XML Declaration Preservation
          # Detect if input had declaration and extract version/encoding
          xml_decl_info = DeclarationHandler.extract_xml_declaration(xml)

          # Store both parsed document (for native DOCTYPE) and extracted info (for model)
          @parsed_doc = parsed
          @root = NokogiriElement.new(parsed.root)
          new(@root, parsed.encoding,
              parsed_doc: parsed,
              doctype: doctype_info,
              xml_declaration: xml_decl_info)
        end

        def to_xml(options = {})
          # Accept xml_declaration from options if present (for model serialization)
          @xml_declaration = options[:xml_declaration] if options[:xml_declaration]

          builder_options = {}
          encoding = determine_encoding(options)
          builder_options[:encoding] = encoding if encoding

          builder = Builder::Nokogiri.build(builder_options) do |xml|
            if root.is_a?(Lutaml::Xml::NokogiriElement)
              # Case A: Old parsed XML (from NokogiriElement) - use build_xml
              root.build_xml(xml)
            else
              # Cases B & C: XmlElement or Model instance
              # ARCHITECTURE: Normalize to XmlElement, then use single rendering path

              # Determine the source (XmlElement or model instance)
              original_model = nil

              xml_element = if root.is_a?(Lutaml::Xml::DataModel::XmlElement)
                              # Case B: Already an XmlElement
                              root
                            else
                              # Case C: Model instance - transform to XmlElement
                              original_model = root
                              mapper_class = options[:mapper_class] || root.class
                              transformation = mapper_class.transformation_for(
                                :xml, @register
                              )
                              transformation.transform(root, options)
                            end

              # Collect original namespace URIs for namespace alias support.
              # This enables round-trip fidelity when XML uses alias URIs.
              original_ns_uris = {}
              stored_plan = nil
              if original_model
                # Case C: Model instance was transformed to XmlElement
                mapping_for_original = options[:mapper_class]&.mappings_for(:xml) || original_model.class.mappings_for(:xml)
                original_ns_uris = collect_original_namespace_uris(
                  original_model, mapping_for_original
                )
                # Get stored xml_declaration_plan from model for PRESERVATION phase
                stored_plan = original_model.xml_declaration_plan if original_model.respond_to?(:xml_declaration_plan)
              elsif xml_element.is_a?(Lutaml::Xml::DataModel::XmlElement)
                # Case B: XmlElement from transformation may have @__xml_original_namespace_uri
                original_ns_uri = xml_element.instance_variable_get(:@__xml_original_namespace_uri)
                if original_ns_uri
                  # Get mapping from the mapper_class (model class) not from XmlElement
                  mapper_klass = options[:mapper_class] || xml_element.class
                  xml_mapping = begin
                    mapper_klass.mappings_for(:xml)
                  rescue StandardError
                    nil
                  end
                  if xml_mapping&.namespace_class
                    canonical_uri = xml_mapping.namespace_class.uri
                    if canonical_uri != original_ns_uri
                      original_ns_uris[canonical_uri] =
                        original_ns_uri
                    end
                  end
                end
              end
              options_with_original_ns = options.merge(__original_namespace_uris: original_ns_uris)
              if stored_plan
                options_with_original_ns[:stored_xml_declaration_plan] =
                  stored_plan
              end

              mapper_class = options[:mapper_class] || xml_element.class
              mapping = mapper_class.mappings_for(:xml)

              # Phase 1: Collect namespace needs from XmlElement tree
              collector = NamespaceCollector.new(@register)
              needs = collector.collect(xml_element, mapping,
                                        mapper_class: mapper_class)

              # Phase 2: Plan namespace declarations (builds ElementNode tree)
              planner = DeclarationPlanner.new(@register)
              plan = planner.plan(xml_element, mapping, needs,
                                  options: options_with_original_ns)

              # Phase 3: Render using XmlElement + DeclarationPlan
              # Pass original model for custom method invocation
              render_options = options.merge(is_root_element: true)
              render_options[:original_model] = original_model if original_model
              build_xml_element_with_plan(xml, xml_element, plan,
                                          render_options)
            end
          end

          xml_options = {}
          # CRITICAL: Explicitly tell Nokogiri NOT to add XML declaration
          # We handle declarations manually with generate_declaration() for full control
          # This ensures no duplicate declarations and proper preservation of input format
          save_options = ::Nokogiri::XML::Node::SaveOptions::NO_DECLARATION |
            ::Nokogiri::XML::Node::SaveOptions::AS_XML

          # Handle indentation and formatting
          # Nokogiri's default behavior is to pretty-print XML
          # We maintain this default for backwards compatibility
          case options[:pretty]
          when true
            xml_options[:indent] = 2
            save_options |= ::Nokogiri::XML::Node::SaveOptions::FORMAT
          when false
            # Explicitly disable formatting - compact output
            # No additional options needed, just don't add FORMAT
          else
            # No pretty option specified - use default pretty-printing for backwards compat
            save_options |= ::Nokogiri::XML::Node::SaveOptions::FORMAT
          end

          xml_options[:save_with] = save_options

          xml_data = builder.doc.root.to_xml(xml_options)

          result = ""

          # Handle XML declaration based on Issue #1: XML Declaration Preservation
          # Include declaration when encoding is specified OR when declaration is requested
          if (options[:encoding] && !options[:encoding].nil?) || should_include_declaration?(options)
            result += generate_declaration(options)
          end

          # Use native Nokogiri DOCTYPE from parsed document if available
          if @parsed_doc&.internal_subset && !options[:omit_doctype]
            result += "#{@parsed_doc.internal_subset}\n"
          elsif options[:doctype] && !options[:omit_doctype]
            # Fallback for model serialization with stored doctype
            result += generate_doctype_declaration(options[:doctype])
          end

          result += xml_data

          # Post-process: Fix OOXML format issues (opt-in)
          result = fix_ooxml_format(result) if options[:fix_boolean_elements]

          result
        end

        # Build element using prepared namespace declaration plan
        #
        # @param xml [Builder] the XML builder
        # @param element [Object] the model instance
        # @param plan [Hash] the declaration plan from DeclarationPlanner
        # @param options [Hash] serialization options
        def build_element_with_plan(xml, element, plan, options = {})
          # Provide default empty plan if nil (e.g., for custom methods)
          plan ||= DeclarationPlan.empty

          mapper_class = options[:mapper_class] || element.class

          # New: Handle simple types that don't have mappings
          unless mapper_class.is_a?(Class) && mapper_class.include?(Lutaml::Model::Serialize)
            tag_name = options[:tag_name] || "element"
            xml.create_and_add_element(tag_name) do |inner_xml|
              inner_xml.text(element.to_s)
            end
            return xml
          end

          mapping = mapper_class.mappings_for(:xml)
          return xml unless mapping

          # TYPE-ONLY MODELS: No element wrapper, serialize children directly
          # BUT if we have a tag_name in options, that means parent wants a wrapper
          if mapping.namespace_class
            # Check if this element's namespace is explicitly :blank
            # This happens when the model uses 'namespace :blank' in its xml block
            # We can detect this through the plan - but since we're inside build_element_with_plan,
            # we need to check the mapping directly
            # Actually, the element itself won't have explicit_blank in its namespace resolution
            # because it's the element's OWN namespace. We need to skip this for the element itself.
            # The xmlns="" handling is for CHILD elements, not the parent element.
            # So this section is actually not needed here - it's needed in add_simple_value
            # But it reads:
            # @mapping.namespace_class
            # element.ns_info_for(repository_name, mapping.xml_namespace)
          end

          # Use xmlns declarations from plan
          attributes = {}
          attributes.merge!(NamespaceDeclarationBuilder.build_xmlns_attributes(plan))

          # Collect attribute custom methods to call after element creation
          attribute_custom_methods = []

          # Add regular attributes (non-xmlns)
          mapping.attributes.each do |attribute_rule|
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

            value = attr.serialize(value, :xml, @register) if attr
            value = ExportTransformer.call(value, attribute_rule, attr,
                                           format: :xml)

            if render_element?(attribute_rule, element, value)
              # Resolve attribute namespace using extracted module
              ns_info = AttributeNamespaceResolver.resolve(
                rule: attribute_rule,
                attribute: attr,
                plan: plan,
                mapper_class: mapper_class,
                register: @register,
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
          prefix_info = ElementPrefixResolver.resolve(mapping: mapping,
                                                      plan: plan)
          prefix = prefix_info[:prefix]
          ns_decl = prefix_info[:ns_decl]

          # Check if element's own namespace needs local declaration (out of scope)
          if ns_decl&.local_on_use?
            # FIX: Handle both default (nil prefix) and prefixed namespaces
            xmlns_attr = if prefix
                           "xmlns:#{prefix}"
                         else
                           "xmlns"
                         end
            attributes[xmlns_attr] = ns_decl.uri
          end

          # W3C COMPLIANCE: Detect if element needs xmlns="" using extracted module
          if BlankNamespaceHandler.needs_xmlns_blank?(mapping: mapping,
                                                      options: options)
            attributes["xmlns"] = ""
          end

          # Native type inheritance fix: handle local_on_use xmlns="" even if parents uses default format
          xmlns_prefix = nil
          xmlns_ns = nil
          if mapping&.namespace_class && plan
            xmlns_ns = plan.namespace_for_class(mapping.namespace_class)
            xmlns_prefix = xmlns_ns&.prefix
          end
          if xmlns_ns&.local_on_use? && !mapping.namespace_uri
            attributes["xmlns:#{xmlns_prefix}"] =
              xmlns_ns&.uri || mapping.namespace_uri
          end

          tag_name = options[:tag_name] || mapping.root_element
          return if options[:except]&.include?(tag_name)

          # Track if THIS element uses default namespace format
          # Children will need this info to know if they should add xmlns=""
          this_element_uses_default_ns = mapping.namespace_class &&
            plan.namespace_for_class(mapping.namespace_class)&.default_format?

          # Get element_form_default from this element's namespace for children
          parent_element_form_default = mapping.namespace_class&.element_form_default

          xml.create_and_add_element(tag_name, attributes: attributes,
                                               prefix: prefix) do |xml|
            # Call attribute custom methods now that element is created
            attribute_custom_methods.each do |attribute_rule|
              mapper_class.new.send(attribute_rule.custom_methods[:to],
                                    element, xml.parent, xml)
            end

            if ordered?(element, options.merge(mapper_class: mapper_class))
              build_ordered_element_with_plan(xml, element, plan,
                                              options.merge(
                                                mapper_class: mapper_class,
                                                parent_prefix: prefix,
                                                parent_uses_default_ns: this_element_uses_default_ns,
                                                parent_element_form_default: parent_element_form_default,
                                                parent_ns_decl: ns_decl,
                                              ))
            else
              build_unordered_children_with_plan(xml, element, plan,
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

        # Build element children in the original order (for ordered content)
        #
        # This method preserves the order of elements as they appeared in the
        # original XML, using element.element_order to iterate through elements.
        #
        # @param xml [Builder] XML builder
        # @param element [Object] model instance
        # @param plan [DeclarationPlan] namespace declaration plan

        # NOTE: build_unordered_children_with_plan and build_ordered_element_with_plan
        # are inherited from BaseAdapter - no need to override

        def build_nested_element_with_plan(xml, value, element_rule,
    attribute_def, plan, options, parent_plan: nil)
          if value.is_a?(Lutaml::Model::Collection)
            items = value.collection
            attr_type = attribute_def.type(@register)

            if attr_type <= Lutaml::Model::Type::Value
              # Simple types - serialize each item
              items.each do |val|
                build_element_value_with_plan(xml, element_rule, val, attribute_def,
                                              plan: plan, mapping: nil, options: options.merge(element: val))
              end
            else
              # Model types - build elements
              items.each do |val|
                # For polymorphic collections, use each item's actual class
                item_mapper_class = if polymorphic_value?(attribute_def, val)
                                      val.class
                                    else
                                      attr_type
                                    end

                # Collect and plan for each item
                item_mapping = item_mapper_class.mappings_for(:xml)
                if item_mapping
                  collector = NamespaceCollector.new(@register)
                  item_needs = collector.collect(val, item_mapping)

                  planner = DeclarationPlanner.new(@register)
                  item_plan = planner.plan(val, item_mapping, item_needs,
                                           parent_plan: plan, options: options)
                else
                  item_plan = plan
                end

                # Performance: Use dup with direct assignment to avoid merge allocations
                # when mapper_class differs from current
                if options[:mapper_class] == item_mapper_class
                  item_options = options
                else
                  item_options = options.dup
                  item_options[:mapper_class] = item_mapper_class
                end
                if item_plan
                  build_element_with_plan(xml, val, item_plan, item_options)
                else
                  build_element(xml, val, item_options)
                end
              end
            end
          else
            # Single Serialize instance
            # Performance: Use dup with direct assignment
            child_mapper = attribute_def.type(@register)
            if options[:mapper_class] == child_mapper
              child_options = options
            else
              child_options = options.dup
              child_options[:mapper_class] = child_mapper
            end
            build_element_with_plan(xml, value, plan, child_options)
          end
        end

        # Build simple element value with plan
        #
        # @param xml [Builder] XML builder
        # @param element_rule [MappingRule] element mapping rule
        # @param value [Object] value to serialize
        # @param attribute_def [Attribute] attribute definition
        # @param plan [DeclarationPlan] namespace plan
        # @param mapping [Xml::Mapping] optional mapping
        # @param options [Hash] serialization options
        def build_element_value_with_plan(xml, element_rule, value,
    attribute_def, plan:, mapping: nil, options: {})
          # Handle array values by creating multiple elements
          if value.is_a?(Array)
            value.each do |val|
              build_element_value_with_plan(xml, element_rule, val, attribute_def,
                                            plan: plan, mapping: mapping, options: options)
            end
            return
          end

          return unless render_element?(element_rule, options[:element], value)

          # Get namespace info for this element
          mapping_local = mapping || options[:mapper_class]&.mappings_for(:xml)
          ns_info = if mapping_local
                      # Try to resolve namespace using local mapping
                      begin
                        NamespaceResolver.new(@register).resolve_for_element(
                          element_rule, attribute_def, mapping_local, plan, options
                        )
                      rescue StandardError
                        # Fallback to default behavior
                        { prefix: nil, ns_info: nil }
                      end
                    else
                      { prefix: nil, ns_info: nil }
                    end

          prefix = ns_info[:prefix]

          # Get child's plan if available
          child_plan = plan&.child_plan(element_rule.to)

          if value.is_a?(Lutaml::Model::Serialize)
            # Nested Serialize object
            child_mapper_class = value.class
            child_mapper_class.mappings_for(:xml)

            # Performance: Use dup with direct assignment to avoid merge allocations
            if options[:mapper_class] == child_mapper_class
              child_options = options
            else
              child_options = options.dup
              child_options[:mapper_class] = child_mapper_class
            end

            if child_plan
              build_element_with_plan(xml, value, child_plan, child_options)
            else
              build_element(xml, value, child_options)
            end
          elsif value.nil? && element_rule.render_nil?
            # Render nil value
            element_name = element_rule.multiple_mappings? ? element_rule.name.first : element_rule.name
            xml.create_and_add_element(element_name,
                                       prefix: prefix) do |inner_xml|
              inner_xml.text("")
            end
          elsif value
            # Simple string value
            element_name = element_rule.multiple_mappings? ? element_rule.name.first : element_rule.name
            xml.create_and_add_element(element_name,
                                       prefix: prefix) do |inner_xml|
              if element_rule.cdata
                inner_xml.cdata(value.to_s)
              else
                inner_xml.text(value.to_s)
              end
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
        def build_xml_element(xml, element, parent_uses_default_ns: false,
    parent_element_form_default: nil, parent_namespace_class: nil)
          # Prepare attributes hash
          attributes = {}

          # Determine if attributes should be qualified based on element's namespace
          element_ns_class = element.namespace_class
          attribute_form_default = element_ns_class&.attribute_form_default || :unqualified
          element_prefix = element_ns_class&.prefix_default

          # Get element_form_default for children
          # Only set when explicitly configured, not when defaulted to :unqualified
          this_element_form_default = if element_ns_class&.element_form_default_set?
                                        element_ns_class.element_form_default
                                      end

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
            attributes[attr_name] = attr.value
          end

          # Determine element name with namespace prefix
          tag_name = element.name
          # CRITICAL FIX: element_form_default: :qualified means child elements inherit parent's namespace PREFIX
          # even when child has NO explicit namespace_class
          prefix = if element_ns_class && element_prefix
                     # Element has explicit prefix_default - use prefix format
                     element_prefix
                   elsif !element_ns_class && parent_element_form_default == :qualified && parent_namespace_class&.prefix_default
                     # Child has NO namespace, but parent has :qualified form_default
                     # Child should INHERIT parent's namespace PREFIX
                     parent_namespace_class.prefix_default
                   else
                     # No prefix (default format or no parent namespace)
                     nil
                   end

          # Track if THIS element uses default namespace format for children
          this_element_uses_default_ns = false

          # Add namespace declaration if element has namespace
          if element.namespace_class
            ns_uri = element.namespace_class.uri

            if prefix
              attributes["xmlns:#{prefix}"] = ns_uri
              # W3C Compliance: When parent uses default namespace and child declares
              # a DIFFERENT prefixed namespace, child must also add xmlns="" to prevent
              # its children from inheriting parent's default namespace
              if parent_uses_default_ns
                attributes["xmlns"] = ""
              end
            else
              attributes["xmlns"] = ns_uri
              this_element_uses_default_ns = true
            end
          elsif parent_uses_default_ns
            # W3C Compliance: Element has no namespace (blank namespace)
            # Check if should inherit parent's namespace based on element_form_default
            # Parent uses default namespace format
            if parent_element_form_default == :qualified
              # Child should INHERIT parent's namespace - no xmlns="" needed
              # The child is in parent namespace (qualified)
            elsif parent_element_form_default == :unqualified
              # Parent's element_form_default is :unqualified - child should be in blank namespace
              # WITHOUT xmlns="" (no xmlns attribute at all). The child is simply
              # not in any namespace, which is the correct W3C behavior for unqualified.
            else
              # element_form_default is not set (nil/default :unqualified)
              # Child needs xmlns="" to explicitly opt out of parent's default namespace
              attributes["xmlns"] = ""
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
            # Add text content if present
            if element.text_content
              # Check if content should be wrapped in CDATA
              if element.cdata
                inner_xml.cdata(element.text_content)
              else
                add_text_with_entities(inner_xml.parent,
                                       element.text_content.to_s, inner_xml.doc)
              end
            end

            # Recursively build child elements, passing namespace context
            element.children.each do |child|
              if child.is_a?(Lutaml::Xml::DataModel::XmlElement)
                build_xml_element(inner_xml, child,
                                  parent_uses_default_ns: this_element_uses_default_ns,
                                  parent_element_form_default: this_element_form_default,
                                  parent_namespace_class: element_ns_class)
              elsif child.is_a?(String)
                inner_xml.text(child)
              end
            end
          end
        end

        # Build XML from XmlDataModel::XmlElement using DeclarationPlan tree (PARALLEL TRAVERSAL)
        #
        # Manually constructs Nokogiri::XML::Node tree to avoid Builder namespace bugs.
        #
        # @param xml [Builder] XML builder (provides doc access)
        # @param xml_element [XmlDataModel::XmlElement] Element content
        # @param plan [DeclarationPlan] Declaration plan with tree structure
        # @param options [Hash] Serialization options
        def build_xml_element_with_plan(xml, xml_element, plan, options = {})
          doc = xml.respond_to?(:doc) ? xml.doc : xml.xml.doc

          root_node = build_nokogiri_node(xml_element, plan.root_node, doc,
                                          plan.global_prefix_registry, nil, options: options, plan: plan)
          doc.root = root_node
        end

        private

        # Recursively build Nokogiri::XML::Node tree manually
        #
        # @param xml_element [XmlDataModel::XmlElement] Content
        # @param element_node [ElementNode] Decisions
        # @param doc [Nokogiri::XML::Document] Document
        # @param global_registry [Hash] Global prefix registry (URI => prefix)
        # @param parent [Nokogiri::XML::Element, nil] Parent element for namespace inheritance
        # @param options [Hash] Serialization options
        # @param plan [DeclarationPlan] Declaration plan with original namespace URIs
        # @param previous_sibling_had_xmlns_blank [Boolean] Previous sibling had xmlns="" for W3C optimization
        # @return [Nokogiri::XML::Element] Created node
        def build_nokogiri_node(xml_element, element_node, doc,
    global_registry, parent = nil, options: {}, plan: nil, previous_sibling_had_xmlns_blank: false)
          qualified_name = element_node.qualified_name

          # Split qualified_name to get prefix and local_name
          # IMPORTANT: Only split on SINGLE colon (namespace prefix separator),
          # not on double colon (::) which is a Ruby module path separator.
          # e.g., "prefix:name" should split to ["prefix", "name"]
          # but "Module::Class" should NOT be split (use whole name as local_name)
          if qualified_name.include?(":") && !qualified_name.include?("::")
            _, local_name = qualified_name.split(":", 2)
          else
            local_name = qualified_name
          end

          # Create element with LOCAL NAME ONLY (no prefix in element name)
          element = ::Nokogiri::XML::Element.new(local_name, doc)

          # Add xmlns declarations FIRST (before adding to parent!)
          # This ensures the element's own namespace is declared before it can inherit parent's
          # Keys: nil = default namespace, "prefix" = prefixed namespace
          original_ns_uris = plan&.original_namespace_uris || {}
          use_prefix_option = options[:use_prefix]
          element_node.hoisted_declarations.each do |key, uri|
            next if uri == "http://www.w3.org/XML/1998/namespace"

            # Convert FPI to URN if necessary (Nokogiri requires valid URI)
            # Only apply original_ns_uris conversion when preserving original format.
            # When use_prefix is explicitly set, we're using system's format preferences.
            effective_uri = if self.class.fpi?(uri)
                              self.class.fpi_to_urn(uri)
                            elsif use_prefix_option.nil?
                              # Preserving original format - use alias URIs from original
                              original_ns_uris[uri] || uri
                            else
                              # Using explicit format preference - use canonical URIs
                              uri
                            end

            if key.nil?
              # Default namespace (xmlns="uri")
              element.add_namespace(nil, effective_uri)
            else
              # Prefixed namespace (xmlns:prefix="uri")
              element.add_namespace(key, effective_uri)
            end
          end

          # NOW set element's namespace (before adding to parent)
          # This ensures the element uses its own namespace, not inherited from parent
          # CRITICAL: Use the decision's namespace_class from element_node, not the element's namespace_class
          # The decision's namespace_class may be nil (blank namespace) even if the element has a namespace_class
          # set during transformation (e.g., when form: :unqualified is set)
          #
          # IMPORTANT: Use xml_element's namespace_class for the namespace decision
          # The element_node (DeclarationPlan::ElementNode) doesn't have namespace_class
          # because namespace decisions are stored in the xml_element during transformation
          #
          # IMPORTANT: When xml_element.namespace_class is nil, check if this is an explicit decision
          # (blank namespace) or if no decision was made. We can tell by checking if the element has
          # a form attribute set to :unqualified.
          target_namespace_class = xml_element.namespace_class
          # Check if this is an explicit "blank namespace" decision (form: :unqualified)
          # If so, don't fall back to any namespace_class
          if target_namespace_class.nil? && xml_element.respond_to?(:form) && xml_element.form == :unqualified
            # Explicit blank namespace decision - don't set any namespace
            target_namespace_class = nil
          end
          # Note: If no explicit decision, we keep target_namespace_class as nil
          # and don't fall back to anything (no default namespace_class)

          if target_namespace_class && target_namespace_class != :blank
            # Use the prefix to find the namespace when available.
            # This is more reliable than matching by URI because hoisted_declarations
            # may contain canonical URIs while the actual namespace was added using
            # alias URIs (via original_ns_uris conversion).
            target_prefix = element_node.use_prefix
            if target_prefix
              # Find namespace by prefix (most reliable - prefix is unique per element)
              ns = element.namespace_scopes.find do |n|
                n.prefix == target_prefix
              end
            else
              # Fall back to URI-based lookup for default namespace
              target_uri = target_namespace_class.uri
              ns = element.namespace_scopes.find do |n|
                n.href == target_uri && n.prefix.nil?
              end
            end
            if ns
              element.namespace = ns
            elsif target_prefix
              # CRITICAL FIX: Check if namespace is declared on parent before adding locally
              # When parent declares the namespace with the SAME format (prefix or default),
              # child should use parent's namespace declaration without re-declaring it.
              # Also check namespace aliases: if parent declared alias URI and child uses
              # canonical URI (or vice versa), the namespace is already established on parent.
              target_prefix = element_node.use_prefix
              parent_has_namespace = parent_has_matching_namespace?(parent, target_uri,
                                                                    target_namespace_class)

              if parent_has_namespace
                # Parent has the namespace declared - find the matching namespace object
                # Must check all URIs (canonical + aliases) since parent may have declared
                # with an alias URI while child uses canonical (or vice versa)
                matching_uris = if target_namespace_class.respond_to?(:all_uris)
                                  target_namespace_class.all_uris
                                else
                                  [target_uri]
                                end
                parent_ns = if target_prefix
                              parent.namespace_scopes.find do |n|
                                matching_uris.include?(n.href) && n.prefix == target_prefix
                              end
                            else
                              parent.namespace_scopes.find do |n|
                                matching_uris.include?(n.href) && n.prefix.nil?
                              end
                            end

                if parent_ns
                  # Parent has the SAME format declaration - use parent's namespace
                  # Set element's namespace to parent's namespace (after adding to parent)
                  # We need to defer setting the namespace until after adding to parent
                  # Store the parent namespace for later use
                  @deferred_namespace = parent_ns
                  nil
                else
                  # Parent has different format - add namespace declaration locally
                  if target_prefix.nil?
                    # Default format: add xmlns="uri" declaration
                    element.add_namespace(nil, target_uri)
                    # Find the newly added namespace and set it
                    ns = element.namespace_scopes.find do |n|
                      n.href == target_uri
                    end
                  else
                    # Prefix format: add xmlns:prefix="uri" declaration
                    element.add_namespace(target_prefix, target_uri)
                    # Find the newly added namespace and set it
                    ns = element.namespace_scopes.find do |n|
                      n.href == target_uri && n.prefix == target_prefix
                    end
                  end
                  element.namespace = ns if ns
                end
              elsif target_prefix.nil?
                # Default format: add xmlns="uri" declaration
                element.add_namespace(nil, target_uri)
                # Find the newly added namespace and set it
                ns = element.namespace_scopes.find { |n| n.href == target_uri }
                element.namespace = ns if ns
              else
                # Prefix format: add xmlns:prefix="uri" declaration
                element.add_namespace(target_prefix, target_uri)
                # Find the newly added namespace and set it
                ns = element.namespace_scopes.find do |n|
                  n.href == target_uri && n.prefix == target_prefix
                end
                element.namespace = ns if ns
              end
            end
          end

          # Add to parent AFTER namespace is set
          # This prevents the element from inheriting parent's namespace before declaring its own
          parent&.add_child(element)

          # CRITICAL FIX: Set deferred namespace after adding to parent
          # This allows the element to use parent's namespace declaration without re-declaring it
          if @deferred_namespace
            element.namespace = @deferred_namespace
            @deferred_namespace = nil
          end

          # CRITICAL FIX: Handle blank namespace elements
          # When element has no namespace_class, it should remain in blank namespace
          # Even if parent uses prefix format, the child should NOT inherit parent's namespace
          # Also applies when form: :unqualified is set (element should be in blank namespace)
          if !xml_element.namespace_class || xml_element.namespace_class == :blank ||
              (xml_element.respond_to?(:form) && xml_element.form == :unqualified)
            # Explicitly set element to blank namespace (no namespace)
            # This prevents the child from inheriting parent's namespace
            element.namespace = nil
          end

          # W3C Compliance: Add xmlns="" if element is in blank namespace
          # and needs to opt out of parent's default namespace
          # W3C Optimization: Only first sibling needs xmlns="", subsequent inherit
          # Only apply optimization when pretty: true is set
          if element_node.needs_xmlns_blank && (options[:pretty] ? !previous_sibling_had_xmlns_blank : true)
            # Add xmlns="" as an attribute (Nokogiri-specific)
            element["xmlns"] = ""
          end

          # Add regular attributes (PARALLEL TRAVERSAL by index)
          # Skip xmlns attributes - they are already declared via hoisted_declarations
          # and setting them as attributes creates duplicate namespace declarations
          xml_element.attributes.each_with_index do |xml_attr, idx|
            attr_name_str = xml_attr.name.to_s
            if attr_name_str.start_with?("xmlns")
              # xmlns attributes from hoisted_declarations are already added above.
              # However, xmlns attributes added by transformation (e.g., xmlns:xsi
              # from @raw_schema_location) may not be in hoisted_declarations.
              # Add them as namespace declarations if not already present.
              if attr_name_str.include?(":")
                prefix = attr_name_str.split(":", 2).last
                unless element_node.hoisted_declarations.key?(prefix)
                  element.add_namespace(prefix, xml_attr.value)
                end
              end
              next
            end

            attr_node = element_node.attribute_nodes[idx]
            element[attr_node.qualified_name] = xml_attr.value
          end

          # Check if element was created from nil value with render_nil option
          # Add xsi:nil="true" attribute for W3C compliance
          if xml_element.respond_to?(:xsi_nil) && xml_element.xsi_nil
            element["xsi:nil"] = true
          end

          # Add schema_location attribute from ElementNode if present
          element_node.schema_location_attr&.each do |attr_name, attr_value|
            element[attr_name] = attr_value
          end

          # Handle raw content (map_all directive)
          # If @raw_content exists, parse and add as XML fragment
          # NOTE: We do NOT return early here because the element may have
          # children that also need to be processed. Raw content should be
          # added alongside children, not replace them.
          if xml_element.respond_to?(:raw_content)
            raw_content = xml_element.raw_content
            if raw_content && !raw_content.to_s.empty?
              # Parse raw content as XML fragment and add children
              fragment = ::Nokogiri::XML.fragment(raw_content.to_s)
              fragment.children.each do |child_node|
                element.add_child(child_node)
              end
              # Do NOT return early - continue to process element's children
            end
          end

          # Recursively build children (PARALLEL TRAVERSAL by index)
          # Pass THIS element as parent so children can inherit namespaces
          child_element_index = 0
          previous_sibling_had_xmlns_blank = false
          xml_element.children.each do |xml_child|
            # Handle EntityReference nodes directly - they have no children
            # and should preserve their entity syntax (e.g., &nbsp;) in round-trips
            if xml_child.is_a?(Lutaml::Xml::NokogiriElement) &&
                xml_child.adapter_node.is_a?(::Nokogiri::XML::EntityReference)
              entity_node = ::Nokogiri::XML::EntityReference.new(doc,
                                                                 xml_child.adapter_node.name)
              element.add_child(entity_node)
              next
            elsif xml_child.is_a?(Lutaml::Xml::DataModel::XmlElement)
              child_node = element_node.element_nodes[child_element_index]
              child_element_index += 1

              # Recurse - child auto-adds itself to element (parent)
              # Pass previous_sibling_had_xmlns_blank for W3C optimization
              build_nokogiri_node(xml_child, child_node, doc, global_registry, element,
                                  options: options, plan: plan,
                                  previous_sibling_had_xmlns_blank: previous_sibling_had_xmlns_blank)
              # Track if this child had xmlns="" for next sibling
              # Blank namespace children get xmlns="" to opt out of parent's default namespace
              if !xml_child.namespace_class && xml_element.namespace_class
                previous_sibling_had_xmlns_blank = true
              end
            elsif xml_child.is_a?(String)
              # Check if parent element has CDATA flag set (for mixed content)
              # Only wrap non-whitespace content in CDATA to avoid extra CDATA sections
              if xml_element.cdata && !xml_child.strip.empty?
                cdata_node = ::Nokogiri::XML::CDATA.new(doc, xml_child)
                element.add_child(cdata_node)
              else
                add_text_with_entities(element, xml_child, doc)
              end
            end
          end

          # Add text content AFTER child elements
          # This ensures mixed content order matches the mapping order
          if xml_element.text_content
            # Check if content should be wrapped in CDATA
            if xml_element.cdata
              cdata_node = ::Nokogiri::XML::CDATA.new(doc,
                                                      xml_element.text_content.to_s)
              element.add_child(cdata_node)
            else
              add_text_with_entities(element, xml_element.text_content.to_s,
                                     doc)
            end
          end

          element
        end

        # Add text content to a Nokogiri element, preserving entity reference patterns.
        # This is used during SERIALIZATION of model attributes that contain user-provided
        # strings. The regex detects entity patterns so they can be preserved as
        # EntityReference nodes rather than being escaped.
        #
        # During PARSING, we do NOT use regex - we rely on Nokogiri's EntityReference nodes.
        #
        # @param element [Nokogiri::XML::Element] parent element to add text to
        # @param text [String] text content (may contain entity patterns from user input)
        # @param doc [Nokogiri::XML::Document] document for node creation
        def add_text_with_entities(element, text, doc)
          entity_pattern = /(&(?:\w+|#\d+|#x[\da-fA-F]+);)/
          parts = text.to_s.split(entity_pattern, -1)
          parts.each do |part|
            next if part.empty?

            if part.match?(/\A&(\w+|#\d+|#x[\da-fA-F]+);\z/)
              entity_name = part[1..-2]
              ent = ::Nokogiri::XML::EntityReference.new(doc, entity_name)
              element.add_child(ent)
            else
              text_node = ::Nokogiri::XML::Text.new(part, doc)
              element.add_child(text_node)
            end
          end
        end

        # Check if parent already has a namespace declaration matching the target URI,
        # including namespace aliases. If parent declared an alias URI and child uses
        # the canonical URI (or another alias of the same namespace), the namespace
        # is already established on parent and child should not re-declare.
        #
        # @param parent [Nokogiri::XML::Element, nil] Parent element
        # @param target_uri [String] The canonical URI the child wants to use
        # @param target_namespace_class [Class] The namespace class with uri_aliases
        # @return [Boolean] true if parent already declares this namespace (exact or alias)
        def parent_has_matching_namespace?(parent, target_uri,
target_namespace_class)
          return false unless parent

          parent_uris = parent.namespace_scopes.map(&:href)

          # Check exact match first
          return true if parent_uris.include?(target_uri)

          # Check if parent declared an alias URI for the same namespace
          if target_namespace_class.respond_to?(:all_uris)
            all_ns_uris = target_namespace_class.all_uris
            return parent_uris.any? { |href| all_ns_uris.include?(href) }
          end

          false
        end

        # Post-process XML string to fix OOXML format issues.
        # Handles two normalization rules:
        # 1. Boolean elements: <w:elem w:val="true"/> -> <w:elem/>
        # 2. XML namespace attribute: <w:t w:xml:space=...> -> <w:t xml:space=...>
        #
        # @param xml [String] The XML string to process
        # @return [String] The processed XML string
        # OOXML boolean element names: self-closing elements where presence = true.
        # This is a whitelist of known boolean element names to avoid incorrectly
        # transforming non-boolean elements like numId, colSpan, etc.
        OOXML_BOOLEAN_ELEMENTS = %w[
          b i strike bCs iCs smallCaps caps vanish noProof
          shadow emboss imprint keepNext keepLines outline
          tblHeader cantSplit contextualSpacing highlight
          rPr pPr trPr tcPr
        ].freeze

        def fix_ooxml_format(xml)
          # Build regex pattern that only matches known boolean element names
          bool_elem_pattern = OOXML_BOOLEAN_ELEMENTS.join("|")

          # Fix self-closing: <ns:elem w:val="true"/> or <ns:elem w:val="1"/>
          # Only for known boolean elements
          xml = xml.gsub(
            /<([a-zA-Z][a-zA-Z0-9]*):(#{bool_elem_pattern})(\s+w:val=")(true|1)("\s*\/?>)/,
          ) { "<#{$1}:#{$2}/>" }

          # Fix with content: <ns:elem w:val="true">true</ns:elem> or <ns:elem w:val="1">1</ns:elem>
          xml = xml.gsub(
            /<([a-zA-Z][a-zA-Z0-9]*):(#{bool_elem_pattern})(\s+w:val=")(true|1)(">)true<\/\1:\2>/,
          ) { "<#{$1}:#{$2}>" }

          # Fix content-only: <ns:elem>true</ns:elem> -> <ns:elem/>
          # For elements that serialize boolean value as text content
          xml = xml.gsub(
            /<([a-zA-Z][a-zA-Z0-9]*):(#{bool_elem_pattern})>true<\/\1:\2>/,
          ) { "<#{$1}:#{$2}/>" }

          # Fix xml:space attribute: <w:t w:xml:space=...> -> <w:t xml:space=...>
          # The xml: attribute belongs to the xml: namespace, not w:
          xml.gsub(/\bw:xml:space=/, "xml:space=")
        end
      end
    end
  end
end
