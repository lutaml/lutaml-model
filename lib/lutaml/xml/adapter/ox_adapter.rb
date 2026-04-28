require "moxml/adapter/ox"

module Lutaml
  module Xml
    module Adapter
      class OxAdapter < BaseAdapter
        extend DocTypeExtractor
        extend AdapterHelpers

        TEXT_CLASSES = [Moxml::Text, Moxml::Cdata].freeze

        def self.parse(xml, options = {})
          enc = encoding(xml, options)

          parsed = begin
            Moxml::Adapter::Ox.parse(xml, encoding: enc)
          rescue Moxml::ParseError => e
            raise Lutaml::Model::InvalidFormatError.new(
              :xml,
              e.message,
            )
          end
          root_element = parsed.root

          # Validate that we have a root element
          if root_element.nil?
            raise Lutaml::Model::InvalidFormatError.new(
              :xml,
              "Document has no root element. " \
              "The XML may be empty, contain only whitespace, " \
              "or consist only of an XML declaration.",
            )
          end

          # Extract DOCTYPE information if present
          # Moxml/Ox doesn't directly expose DOCTYPE, extract from raw XML
          doctype_info = extract_doctype_from_xml(xml)

          @root = Ox::Element.new(root_element)
          @root.processing_instructions = extract_document_processing_instructions(parsed)
          new(@root, enc, doctype: doctype_info)
        end

        def to_xml(options = {})
          # Accept xml_declaration from options if present (for model serialization)
          @xml_declaration = options[:xml_declaration] if options[:xml_declaration]

          builder_options = {}
          encoding = determine_encoding(options)
          builder_options[:encoding] = encoding if encoding

          builder = Builder::Ox.build(builder_options) do |xml|
            if @root.is_a?(Ox::Element)
              @root.build_xml(xml)
            else
              original_model = nil

              xml_element = if @root.is_a?(Lutaml::Xml::DataModel::XmlElement)
                              @root
                            else
                              mapper_class = options[:mapper_class] || @root.class
                              xml_mapping = mapper_class.mappings_for(:xml)

                              has_custom_map_all = xml_mapping.raw_mapping&.custom_methods &&
                                xml_mapping.raw_mapping.custom_methods[:to]

                              if has_custom_map_all
                                nil
                              else
                                original_model = @root
                                transformation = mapper_class.transformation_for(
                                  :xml, register
                                )
                                transformation.transform(@root, options)
                              end
                            end

              if xml_element
                mapper_class = options[:mapper_class] || xml_element.class
                mapping = mapper_class.mappings_for(:xml)

                collector = NamespaceCollector.new(register)
                needs = collector.collect(xml_element, mapping,
                                          mapper_class: mapper_class)

                planner = DeclarationPlanner.new(register)
                plan = planner.plan(xml_element, mapping, needs,
                                    options: options)

                render_options = options.merge(is_root_element: true)
                if original_model
                  render_options[:original_model] =
                    original_model
                end
                build_xml_element_with_plan(xml, xml_element, plan,
                                            render_options)
              else
                mapper_class = options[:mapper_class] || @root.class
                xml_mapping = mapper_class.mappings_for(:xml)

                collector = NamespaceCollector.new(register)
                needs = collector.collect(@root, xml_mapping)

                planner = DeclarationPlanner.new(register)
                plan = planner.plan(@root, xml_mapping, needs, options: options)

                build_element_with_plan(xml, @root, plan, options)
              end
            end
          end

          xml_data = builder.to_xml

          result = ""
          # Use DeclarationHandler methods instead of Document#declaration
          # Include declaration when encoding is specified OR when declaration is requested
          if (options[:encoding] && !options[:encoding].nil?) || options[:declaration]
            result += generate_declaration(options)
          end

          # Add DOCTYPE if present - use DeclarationHandler method
          doctype_to_use = options[:doctype] || @doctype
          if doctype_to_use && !options[:omit_doctype]
            result += generate_doctype_declaration(doctype_to_use)
          end

          result += xml_data
          result
        end

        # Build XML from XmlDataModel::XmlElement using DeclarationPlan tree (PARALLEL TRAVERSAL)
        #
        # @param builder [Builder::Ox] XML builder
        # @param xml_element [XmlDataModel::XmlElement] Element content
        # @param plan [DeclarationPlan] Declaration plan with tree structure
        # @param options [Hash] Serialization options
        def build_xml_element_with_plan(builder, xml_element, plan,
_options = {})
          # Add processing instructions before root element
          xml_element.processing_instructions.each do |pi|
            builder.add_processing_instruction(pi.target, pi.content)
          end

          build_ox_node(builder, xml_element, plan.root_node,
                        plan.global_prefix_registry, plan: plan)
        end

        private

        # Recursively build XML element tree manually (PARALLEL TRAVERSAL)
        #
        # @param xml [Builder::Ox] XML builder
        # @param xml_element [XmlDataModel::XmlElement] Content
        # @param element_node [ElementNode] Decisions
        # @param global_registry [Hash] Global prefix registry (URI => prefix)
        # @param plan [DeclarationPlan] Declaration plan with original namespace URIs
        # @return [void]
        def build_ox_node(xml, xml_element, element_node, global_registry,
plan: nil)
          qualified_name = element_node.qualified_name

          # 1. Collect attributes (xmlns declarations + regular attributes)
          attributes = {}

          # 2. Add hoisted xmlns declarations
          original_ns_uris = plan&.original_namespace_uris || {}
          element_node.hoisted_declarations.each do |key, uri|
            next if uri == "http://www.w3.org/XML/1998/namespace"

            # Convert FPI to URN if necessary (Ox requires valid URI)
            effective_uri = if self.class.fpi?(uri)
                              self.class.fpi_to_urn(uri)
                            else
                              original_ns_uris[uri] || uri
                            end

            xmlns_name = key ? "xmlns:#{key}" : "xmlns"
            attributes[xmlns_name] = effective_uri
          end

          # 3. Add regular attributes by INDEX (PARALLEL TRAVERSAL)
          xml_element.attributes.each_with_index do |xml_attr, idx|
            attr_node = element_node.attribute_nodes[idx]
            attributes[attr_node.qualified_name] = xml_attr.value.to_s
          end

          # Check for xsi:nil
          if xml_element.respond_to?(:xsi_nil) && xml_element.xsi_nil
            attributes["xsi:nil"] = "true"
          end

          # Add schema_location attribute from ElementNode if present
          attributes.merge!(element_node.schema_location_attr) if element_node.schema_location_attr

          # 4. Add xmlns="" if element needs to opt out of parent's default namespace
          if element_node.needs_xmlns_blank
            attributes["xmlns"] = ""
          end

          # 5. Create element with qualified name using block for proper nesting
          xml.create_and_add_element(qualified_name, attributes: attributes) do
            # 6. Handle raw content (map_all directive)
            if xml_element.respond_to?(:raw_content)
              raw_content = xml_element.raw_content
              if raw_content && !raw_content.to_s.empty?
                xml.add_xml_fragment(xml, raw_content.to_s)
                return
              end
            end

            # 7. Add text content if present
            if xml_element.text_content
              if xml_element.cdata
                xml.cdata(xml_element.text_content.to_s)
              else
                xml.text(xml_element.text_content.to_s)
              end
            end

            # 8. Recursively build children by INDEX (PARALLEL TRAVERSAL)
            child_element_index = 0
            xml_element.children.each do |xml_child|
              if xml_child.is_a?(Lutaml::Xml::DataModel::XmlElement)
                child_node = element_node.element_nodes[child_element_index]
                child_element_index += 1

                build_ox_node(xml, xml_child, child_node, global_registry,
                              plan: plan)
              elsif xml_child.is_a?(String)
                xml.text(xml_child)
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
          mapper_class = options[:mapper_class] || element.class
          xml_mapping = mapper_class.mappings_for(:xml)
          return xml unless xml_mapping

          # TYPE-ONLY MODELS: No element wrapper, serialize children directly
          # BUT if we have a tag_name in options, that means parent wants a wrapper
          plan ||= DeclarationPlan.empty

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

          tag_name = options[:tag_name] || xml_mapping.root_element
          return if options[:except]&.include?(tag_name)

          xml.create_and_add_element(tag_name, prefix: prefix,
                                               attributes: attributes.compact) do |el|
            # Call attribute custom methods now that element is created
            attribute_custom_methods.each do |attribute_rule|
              mapper_class.new.send(attribute_rule.custom_methods[:to],
                                    element, el.parent, el)
            end

            if ordered?(element, options.merge(mapper_class: mapper_class))
              build_ordered_element_with_plan(el, element, plan,
                                              options.merge(
                                                mapper_class: mapper_class,
                                                parent_ns_decl: prefix_info[:ns_decl],
                                              ))
            else
              build_unordered_children_with_plan(el, element, plan,
                                                 options.merge(
                                                   mapper_class: mapper_class,
                                                   parent_ns_decl: prefix_info[:ns_decl],
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
            # Ensure attribute value is a string for Ox
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
                   else
                     # Fallback: No prefix (default format or no namespace)
                     # CRITICAL: Child with NO namespace should NEVER get parent's prefix
                     nil
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
                  inner_xml.text(element.text_content.to_s)
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
                  inner_xml.text(child)
                end
              end
            end
          end
        end

        # NOTE: build_unordered_children_with_plan and build_ordered_element_with_plan
        # are inherited from BaseAdapter - no need to override

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
          if value.is_a?(Array)
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
                                  else
                                    nil # Use default format
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

          # Initialize resolved_prefix from namespace resolution
          resolved_prefix = ns_result[:prefix]

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
                                else
                                  # Parent uses default format, child should too (no prefix)
                                  nil
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
            xml.create_and_add_element(rule.name,
                                       attributes: attributes.merge({ "xsi:nil" => true }),
                                       prefix: resolved_prefix)
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

        # NOTE: name_of, prefixed_name_of, namespaced_attr_name, namespaced_name_of
        # are provided by AdapterHelpers module via extend

        def self.text_of(element)
          element.text
        end

        def self.order_of(element)
          element.order
        end
      end
    end
  end
end
