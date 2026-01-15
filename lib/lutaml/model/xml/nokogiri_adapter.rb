require "nokogiri"
require_relative "document"
require_relative "builder/nokogiri"
require_relative "namespace_collector"
require_relative "declaration_planner"
require_relative "declaration_handler"
require_relative "input_namespace_extractor"
require_relative "nokogiri/entity_resolver"
require_relative "nokogiri/element"
require_relative "polymorphic_value_handler"
require_relative "namespace_declaration_builder"
require_relative "attribute_namespace_resolver"
require_relative "element_prefix_resolver"
require_relative "blank_namespace_handler"
require_relative "namespace_resolver"

module Lutaml
  module Model
    module Xml
      class NokogiriAdapter < Document
        include DeclarationHandler
        include PolymorphicValueHandler

        def self.parse(xml, options = {})
          # Pre-process XML to escape unescaped & characters
          # This prevents Nokogiri from dropping data after invalid entities
          xml = escape_unescaped_ampersands(xml)

          parsed = ::Nokogiri::XML(xml, nil, encoding(xml, options))

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

          # Extract input namespace declarations for Issue #3: Namespace Preservation
          # This captures ALL xmlns declarations from the root element
          # These will be preserved during serialization (Tier 1 priority)
          input_namespaces = InputNamespaceExtractor.extract(parsed.root, :nokogiri)

          # Store both parsed document (for native DOCTYPE) and extracted info (for model)
          @parsed_doc = parsed
          @root = NokogiriElement.new(parsed.root)
          new(@root, parsed.encoding,
              parsed_doc: parsed,
              doctype: doctype_info,
              xml_declaration: xml_decl_info,
              input_namespaces: input_namespaces)
        end

        # Extract all xmlns namespace declarations from root element
        #
        # Wrapper method for backwards compatibility with tests.
        # Delegates to InputNamespaceExtractor.
        #
        # @param root_element [Nokogiri::XML::Element] the root element
        # @return [Hash] map of prefix/uri pairs from input
        def self.extract_input_namespaces(root_element)
          InputNamespaceExtractor.extract(root_element, :nokogiri)
        end

        # Escape unescaped ampersands in XML
        # Only escapes & that are NOT part of valid entities (including HTML entities)
        # Valid entities: &xxx; where xxx is alphanumeric, #digits, or #xhex
        def self.escape_unescaped_ampersands(xml)
          # Match & that are NOT followed by entity-like patterns
          # Entity patterns: &name; (alphanumeric), #ddd; (decimal), #xHH; (hex)
          # Negative lookahead: (?![a-zA-Z0-9#]+;)
          # This preserves ALL entities (XML, HTML, custom) while escaping bare &
          xml.gsub(/&(?![a-zA-Z0-9#]+;)/, "&amp;")
        end

        def to_xml(options = {})
          # Accept xml_declaration from options if present (for model serialization)
          @xml_declaration = options[:xml_declaration] if options[:xml_declaration]

          # Accept input_namespaces from options if present (for namespace format preservation)
          @input_namespaces = options[:input_namespaces] if options[:input_namespaces]

          builder_options = {}

          if options.key?(:encoding)
            unless options[:encoding].nil?
              builder_options[:encoding] =
                options[:encoding]
            end
          elsif options.key?(:parse_encoding)
            builder_options[:encoding] = options[:parse_encoding]
          else
            builder_options[:encoding] = "UTF-8"
          end

          builder = Builder::Nokogiri.build(builder_options) do |xml|
            if root.is_a?(Lutaml::Model::Xml::NokogiriElement)
              # Path A: Old parsed XML - use legacy build_xml
              root.build_xml(xml)
            elsif root.is_a?(Lutaml::Model::XmlDataModel::XmlElement)
              # Path B: XmlElement tree (from Transformation)
              # UNIFIED ARCHITECTURE: XmlElement → Three-Phase → XML

              mapper_class = options[:mapper_class] || @root.class
              mapping = mapper_class.mappings_for(:xml)

              # Phase 1: Collect namespace needs from XmlElement tree
              collector = NamespaceCollector.new(@register)
              needs = collector.collect(@root, mapping, mapper_class: mapper_class)

              # Phase 2: Plan namespace declarations (builds ElementNode tree)
              planner = DeclarationPlanner.new(@register)
              plan = planner.plan(@root, mapping, needs, options: options)

              # Phase 3: Render using tree (NEW - parallel traversal)
              build_xml_element_with_plan(xml, @root, plan, options.merge(is_root_element: true))
            else
              # Path C: Model instance
              mapper_class = options[:mapper_class] || @root.class
              mapping = mapper_class.mappings_for(:xml)

              # Check if model has map_all with custom methods
              # Custom methods work with model instances, not XmlElement trees
              has_custom_map_all = mapping.raw_mapping&.custom_methods &&
                                   mapping.raw_mapping.custom_methods[:to]

              if has_custom_map_all
                # Use legacy path for custom methods
                collector = NamespaceCollector.new(@register)
                needs = collector.collect(@root, mapping, mapper_class: mapper_class)

                planner = DeclarationPlanner.new(@register)
                plan = planner.plan(@root, mapping, needs, options: options)

                build_element_with_plan(xml, @root, plan, options)
              else
                # UNIFIED ARCHITECTURE: Model → Transformation → XmlElement → Three-Phase → XML

                # Step 1: Transform model to XmlElement tree
                transformation = mapper_class.transformation_for(:xml, @register)
                xml_element = transformation.transform(@root, options)

                # Step 2: Collect namespace needs from XmlElement tree
                collector = NamespaceCollector.new(@register)
                needs = collector.collect(xml_element, mapping, mapper_class: mapper_class)

                # Step 3: Plan declarations (builds ElementNode tree)
                planner = DeclarationPlanner.new(@register)
                plan = planner.plan(xml_element, mapping, needs, options: options)

                # Step 4: Render using tree (NEW - parallel traversal)
                build_xml_element_with_plan(xml, xml_element, plan, options.merge(is_root_element: true))
              end
            end
          end

          xml_options = {}
          if options[:pretty]
            xml_options[:indent] = 2
          end

          xml_data = builder.doc.root.to_xml(xml_options)

          result = ""

          # Handle XML declaration based on Issue #1: XML Declaration Preservation
          # Include declaration when encoding is specified OR when declaration is requested
          if (options[:encoding] && !options[:encoding].nil?) || should_include_declaration?(options)
            result += generate_declaration(options)
          end

          # Use native Nokogiri DOCTYPE from parsed document if available
          if @parsed_doc&.internal_subset && !options[:omit_doctype]
            result += @parsed_doc.internal_subset.to_s + "\n"
          elsif options[:doctype] && !options[:omit_doctype]
            # Fallback for model serialization with stored doctype
            result += generate_doctype_declaration(options[:doctype])
          end

          result += xml_data
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
          unless mapper_class.respond_to?(:mappings_for)
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

          # Apply namespace declarations from plan using extracted module
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
                register: @register
              )

              # Build qualified attribute name based on W3C semantics
              attr_name = AttributeNamespaceResolver.build_qualified_name(
                ns_info,
                mapping_rule_name,
                attribute_rule
              )
              attributes[attr_name] = value ? value.to_s : value

              # Add local xmlns declaration if needed
              if ns_info[:needs_local_declaration]
                attributes[ns_info[:local_xmlns_attr]] = ns_info[:local_xmlns_uri]
              end
            end
          end

          # Add schema location if present
          if element.respond_to?(:schema_location) && !options[:except]&.include?(:schema_location)
            if element.schema_location.is_a?(Lutaml::Model::SchemaLocation)
              # Programmatic SchemaLocation object
              attributes.merge!(element.schema_location.to_xml_attributes)
            elsif element.instance_variable_defined?(:@raw_schema_location)
              # Raw string from parsing - reconstruct xsi attributes
              raw_value = element.instance_variable_get(:@raw_schema_location)
              if raw_value && !raw_value.empty?
                attributes["xmlns:xsi"] = "http://www.w3.org/2001/XMLSchema-instance"
                attributes["xsi:schemaLocation"] = raw_value
              end
            end
          end

          # Determine prefix from plan using extracted module
          prefix_info = ElementPrefixResolver.resolve(mapping: mapping, plan: plan)
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
          if BlankNamespaceHandler.needs_xmlns_blank?(mapping: mapping, options: options)
            attributes["xmlns"] = ""
          end

          # Native type inheritance fix: handle local_on_use xmlns="" even if parents uses default format
          xmlns_prefix = nil
          xmlns_ns = nil
          if mapping&.namespace_class && plan
            xmlns_ns = plan.namespace_for_class(mapping.namespace_class)
            xmlns_prefix = xmlns_ns&.prefix
          end
          attributes["xmlns:#{xmlns_prefix}"] = xmlns_ns&.uri || mapping.namespace_uri if xmlns_ns&.local_on_use? && !mapping.namespace_uri

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
                                                parent_ns_decl: ns_decl
                                              ))
            else
              build_unordered_children_with_plan(xml, element, plan,
                                                 options.merge(
                                                   mapper_class: mapper_class,
                                                   parent_prefix: prefix,
                                                   parent_uses_default_ns: this_element_uses_default_ns,
                                                   parent_element_form_default: parent_element_form_default,
                                                   parent_ns_decl: ns_decl
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
        def build_xml_element(xml, element, parent_uses_default_ns: false, parent_element_form_default: nil, parent_namespace_class: nil)
          # Prepare attributes hash
          attributes = {}

          # Determine if attributes should be qualified based on element's namespace
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
            attributes[attr_name] = attr.value
          end

          # Determine element name with namespace prefix
          tag_name = element.name
          # CRITICAL FIX: element_form_default: :qualified means child elements inherit parent's namespace PREFIX
          # even when child has NO explicit namespace_class
          prefix = if element_ns_class && element_prefix
                    # Element has explicit prefix_default - use prefix format
                    element_prefix
                  elsif !element_ns_class && parent_element_form_default == :qualified && parent_namespace_class && parent_namespace_class.prefix_default
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
          else
            # W3C Compliance: Element has no namespace (blank namespace)
            # Check if should inherit parent's namespace based on element_form_default
            if parent_uses_default_ns
              # Parent uses default namespace format
              if parent_element_form_default == :qualified
                # Child should INHERIT parent's namespace - no xmlns="" needed
                # The child is in parent namespace (qualified)
              else
                # Parent's element_form_default is :unqualified - child in blank namespace
                # Add xmlns="" to explicitly opt out of parent's default namespace
                attributes["xmlns"] = ""
              end
            end
          end

          # Check if element was created from nil value with render_nil option
          # Add xsi:nil="true" attribute for W3C compliance
          if element.instance_variable_defined?(:@is_nil) && element.instance_variable_get(:@is_nil)
            attributes["xsi:nil"] = true
          end

          # Create element
          xml.create_and_add_element(tag_name, attributes: attributes, prefix: prefix) do |inner_xml|
            # Add text content if present
            if element.text_content
              inner_xml.text(element.text_content)
            end

            # Recursively build child elements, passing namespace context
            element.children.each do |child|
              if child.is_a?(Lutaml::Model::XmlDataModel::XmlElement)
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

          root_node = build_nokogiri_node(xml_element, plan.root_node, doc, plan.global_prefix_registry)
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
        # @return [Nokogiri::XML::Element] Created node
        def build_nokogiri_node(xml_element, element_node, doc, global_registry, parent = nil)
          qualified_name = element_node.qualified_name

          # Split qualified_name to get prefix and local_name
          if qualified_name.include?(":")
            prefix, local_name = qualified_name.split(":", 2)
          else
            prefix = nil
            local_name = qualified_name
          end

          # Create element with LOCAL NAME ONLY (no prefix in element name)
          element = ::Nokogiri::XML::Element.new(local_name, doc)

          # Add xmlns declarations FIRST (before adding to parent!)
          # This ensures the element's own namespace is declared before it can inherit parent's
          # Keys: nil = default namespace, "prefix" = prefixed namespace
          element_node.hoisted_declarations.each do |key, uri|
            next if uri == "http://www.w3.org/XML/1998/namespace"

            if key.nil?
              # Default namespace (xmlns="uri")
              element.add_namespace(nil, uri)
            else
              # Prefixed namespace (xmlns:prefix="uri")
              element.add_namespace(key, uri)
            end
          end

          # NOW set element's namespace (before adding to parent)
          # This ensures the element uses its own namespace, not inherited from parent
          if xml_element.namespace_class && xml_element.namespace_class != :blank
            target_uri = xml_element.namespace_class.uri
            ns = element.namespace_scopes.find { |n| n.href == target_uri }
            if ns
              element.namespace = ns
            else
              # CRITICAL FIX: Namespace not found in scopes
              # This means the element needs to declare its own namespace locally
              # This happens when child element has different namespace from parent
              target_prefix = element_node.use_prefix
              if target_prefix.nil?
                # Default format: add xmlns="uri" declaration
                element.add_namespace(nil, target_uri)
                # Find the newly added namespace and set it
                ns = element.namespace_scopes.find { |n| n.href == target_uri }
                element.namespace = ns if ns
              else
                # Prefix format: add xmlns:prefix="uri" declaration
                element.add_namespace(target_prefix, target_uri)
                # Find the newly added namespace and set it
                ns = element.namespace_scopes.find { |n| n.href == target_uri && n.prefix == target_prefix }
                element.namespace = ns if ns
              end
            end
          end

          # Add to parent AFTER namespace is set
          # This prevents the element from inheriting parent's namespace before declaring its own
          parent.add_child(element) if parent

          # CRITICAL FIX: Handle blank namespace elements
          # When element has no namespace_class, it should remain in blank namespace
          # Even if parent uses prefix format, the child should NOT inherit parent's namespace
          if !xml_element.namespace_class || xml_element.namespace_class == :blank
            # Explicitly set element to blank namespace (no namespace)
            # This prevents the child from inheriting parent's namespace
            element.namespace = nil
          end

          # W3C Compliance: Add xmlns="" if element is in blank namespace
          # and needs to opt out of parent's default namespace
          if element_node.needs_xmlns_blank
            # Add xmlns="" as an attribute (Nokogiri-specific)
            element["xmlns"] = ""
          end

          # Add regular attributes (PARALLEL TRAVERSAL by index)
          xml_element.attributes.each_with_index do |xml_attr, idx|
            attr_node = element_node.attribute_nodes[idx]
            element[attr_node.qualified_name] = xml_attr.value
          end

          # Check if element was created from nil value with render_nil option
          # Add xsi:nil="true" attribute for W3C compliance
          if xml_element.instance_variable_defined?(:@is_nil) && xml_element.instance_variable_get(:@is_nil)
            element["xsi:nil"] = true
          end

          # Handle raw content (map_all directive)
          # If @raw_content exists, parse and add as XML fragment
          if xml_element.instance_variable_defined?(:@raw_content)
            raw_content = xml_element.instance_variable_get(:@raw_content)
            if raw_content && !raw_content.to_s.empty?
              # Parse raw content as XML fragment and add children
              fragment = ::Nokogiri::XML.fragment(raw_content.to_s)
              fragment.children.each do |child_node|
                element.add_child(child_node)
              end
              return element  # Skip text_content and children processing
            end
          end

          # Add text content
          if xml_element.text_content
            text_node = ::Nokogiri::XML::Text.new(xml_element.text_content.to_s, doc)
            element.add_child(text_node)
          end

          # Recursively build children (PARALLEL TRAVERSAL by index)
          # Pass THIS element as parent so children can inherit namespaces
          child_element_index = 0
          xml_element.children.each do |xml_child|
            if xml_child.is_a?(Lutaml::Model::XmlDataModel::XmlElement)
              child_node = element_node.element_nodes[child_element_index]
              child_element_index += 1

              # Recurse - child auto-adds itself to element (parent)
              build_nokogiri_node(xml_child, child_node, doc, global_registry, element)
            elsif xml_child.is_a?(String)
              text_node = ::Nokogiri::XML::Text.new(xml_child, doc)
              element.add_child(text_node)
            end
          end

          element
        end

        public
      end
    end
  end
end
