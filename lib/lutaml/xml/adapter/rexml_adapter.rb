require "rexml/document"
require "moxml"
require "moxml/adapter/rexml"

module Lutaml
  module Xml
    module Adapter
      class RexmlAdapter < BaseAdapter
        extend AdapterHelpers

        TEXT_CLASSES = [Moxml::Text, Moxml::Cdata].freeze

        def self.parse(xml, options = {})
          parse_encoding = encoding(xml, options)
          xml = normalize_xml_for_rexml(xml)

          parsed = Moxml::Adapter::Rexml.parse(xml)
          root_element = parsed.root || parse_with_escaped_ampersands(xml)

          if root_element.nil?
            raise REXML::ParseException.new(
              "Malformed XML: Unable to parse the provided XML document. " \
              "The document structure is invalid or incomplete.",
            )
          end

          @root = Rexml::Element.new(root_element,
                                     target_encoding: parse_encoding)
          new(@root, parse_encoding)
        end

        def to_xml(options = {})
          encoding = determine_encoding(options)
          builder_options = encoding ? { encoding: encoding } : {}

          builder = Builder::Rexml.build(builder_options) do |xml|
            if @root.is_a?(Rexml::Element)
              # Case A: Old parsed XML (from Rexml::Element) - use build_xml
              @root.build_xml(xml)
            else
              # Cases B & C: XmlElement or Model instance
              # ARCHITECTURE: Normalize to XmlElement, then use single rendering path

              # Determine the source (XmlElement or model instance)
              original_model = nil

              xml_element = if @root.is_a?(Lutaml::Xml::DataModel::XmlElement)
                              # Case B: Already an XmlElement
                              @root
                            else
                              # Case C: Model instance - check for custom methods first
                              mapper_class = options[:mapper_class] || @root.class
                              xml_mapping = mapper_class.mappings_for(:xml)

                              # Check if model has map_all with custom methods
                              # Custom methods work with model instances, not XmlElement trees
                              has_custom_map_all = xml_mapping.raw_mapping&.custom_methods &&
                                xml_mapping.raw_mapping.custom_methods[:to]

                              if has_custom_map_all
                                # Use legacy path for custom methods - don't transform
                                nil
                              else
                                # Transform model to XmlElement tree
                                original_model = @root
                                transformation = mapper_class.transformation_for(
                                  :xml, register
                                )
                                transformation.transform(@root, options)
                              end
                            end

              if xml_element
                # Modern path: Use XmlElement + DeclarationPlan tree
                mapper_class = options[:mapper_class] || xml_element.class
                mapping = mapper_class.mappings_for(:xml)

                # Phase 1: Collect namespace needs from XmlElement tree
                collector = NamespaceCollector.new(register)
                needs = collector.collect(xml_element, mapping,
                                          mapper_class: mapper_class)

                # Phase 2: Plan namespace declarations (builds ElementNode tree)
                planner = DeclarationPlanner.new(register)
                plan = planner.plan(xml_element, mapping, needs,
                                    options: options)

                # Phase 3: Render using XmlElement + DeclarationPlan
                render_options = options.merge(is_root_element: true)
                if original_model
                  render_options[:original_model] =
                    original_model
                end
                build_xml_element_with_plan(xml, xml_element, plan,
                                            render_options)
              else
                # Legacy path: Model instance with custom methods
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
          options[:declaration] ? declaration(options) + xml_data : xml_data
        end

        # Build XML from XmlDataModel::XmlElement using DeclarationPlan tree (PARALLEL TRAVERSAL)
        #
        # @param xml [Builder::Rexml] XML builder
        # @param xml_element [XmlDataModel::XmlElement] Element content
        # @param plan [DeclarationPlan] Declaration plan with tree structure
        # @param options [Hash] Serialization options
        def build_xml_element_with_plan(xml, xml_element, plan, _options = {})
          build_rexml_element(xml, xml_element, plan.root_node,
                              plan.global_prefix_registry, plan)
        end

        private

        # Recursively build REXML elements (PARALLEL TRAVERSAL)
        #
        # @param xml [Builder::Rexml] XML builder
        # @param xml_element [XmlDataModel::XmlElement] Content
        # @param element_node [ElementNode] Decisions
        # @param global_registry [Hash] Global prefix registry (URI => prefix)
        # @return [void]
        def build_rexml_element(xml, xml_element, element_node,
global_registry, plan)
          qualified_name = element_node.qualified_name

          # 1. Collect attributes (xmlns declarations + regular attributes)
          attributes = {}

          # 2. Add hoisted xmlns declarations
          original_ns_uris = plan&.original_namespace_uris || {}
          element_node.hoisted_declarations.each do |key, uri|
            next if uri == "http://www.w3.org/XML/1998/namespace"

            # Use original alias URI if available (for namespace alias round-trip fidelity)
            effective_uri = original_ns_uris[uri] || uri
            xmlns_name = key ? "xmlns:#{key}" : "xmlns"
            attributes[xmlns_name] = effective_uri
          end

          # 3. Add regular attributes by INDEX (PARALLEL TRAVERSAL)
          xml_element.attributes.each_with_index do |xml_attr, idx|
            attr_node = element_node.attribute_nodes[idx]
            attributes[attr_node.qualified_name] = xml_attr.value.to_s
          end

          # 4. Add xsi:nil if needed
          if xml_element.instance_variable_defined?(:@is_nil) &&
              xml_element.instance_variable_get(:@is_nil)
            attributes["xsi:nil"] = "true"
          end

          # Add schema_location attribute from ElementNode if present
          attributes.merge!(element_node.schema_location_attr) if element_node.schema_location_attr

          # 5. Add xmlns="" if element needs to opt out of parent's default namespace
          if element_node.needs_xmlns_blank
            attributes["xmlns"] = ""
          end

          # 6. Create element with qualified name and attributes
          xml.create_and_add_element(qualified_name,
                                     attributes: attributes) do |inner_xml|
            # 7. Handle raw content (map_all directive)
            if xml_element.instance_variable_defined?(:@raw_content)
              raw_content = xml_element.instance_variable_get(:@raw_content)
              if raw_content && !raw_content.to_s.empty?
                inner_xml.add_text(inner_xml, raw_content.to_s, cdata: false)
                return
              end
            end

            # 8. Add text content if present
            if xml_element.text_content
              inner_xml.add_text(inner_xml, xml_element.text_content.to_s,
                                 cdata: xml_element.cdata || false)
            end

            # 9. Recursively build children by INDEX (PARALLEL TRAVERSAL)
            child_element_index = 0
            xml_element.children.each do |xml_child|
              if xml_child.is_a?(Lutaml::Xml::DataModel::XmlElement)
                child_node = element_node.element_nodes[child_element_index]
                child_element_index += 1

                build_rexml_element(inner_xml, xml_child, child_node,
                                    global_registry, plan)
              elsif xml_child.is_a?(String)
                inner_xml.add_text(inner_xml, xml_child)
              end
            end
          end
        end

        public

        def attributes_hash(element)
          result = Lutaml::Model::MappingHash.new

          element.attributes.each_value do |attr|
            if attr.name == "schemaLocation"
              result["__schema_location"] = {
                namespace: attr.namespace,
                prefix: attr.namespace.prefix,
                schema_location: attr.value,
              }
            else
              result[self.class.namespaced_attr_name(attr)] = attr.value
            end
          end

          result
        end

        # NOTE: name_of, prefixed_name_of, namespaced_attr_name, namespaced_name_of
        # are provided by AdapterHelpers module via extend

        def self.text_of(element)
          element.content
        end

        def order
          children.map do |child|
            type = child.text? ? "Text" : "Element"
            Element.new(type, child.unprefixed_name)
          end
        end

        def self.order_of(element)
          element.children.map do |child|
            instance_args = if TEXT_CLASSES.include?(child.class)
                              ["Text", "text"]
                            else
                              ["Element", name_of(child)]
                            end
            Element.new(*instance_args)
          end
        end

        def self.normalize_xml_for_rexml(xml)
          return xml unless xml.is_a?(String) && xml.encoding.to_s != "UTF-8"

          xml.encode("UTF-8")
        end

        def self.parse_with_escaped_ampersands(xml)
          return nil unless xml.is_a?(String)

          escaped_xml = xml.gsub(/&(?![a-zA-Z]+;|#[0-9]+;|#x[0-9a-fA-F]+;)/,
                                 "&amp;")
          Moxml::Adapter::Rexml.parse(escaped_xml).root
        end

        def build_element_with_plan(xml, element, plan, options = {})
          mapper_class = options[:mapper_class] || element.class
          xml_mapping = mapper_class.mappings_for(:xml)
          return xml unless xml_mapping

          plan ||= {
            namespaces: {},
            children_plans: {},
            type_namespaces: {},
          }
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
                    child_plan = child_plan_for(plan, element_rule.to) || {
                      namespaces: {},
                      children_plans: {},
                      type_namespaces: {},
                    }
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

                child_plan = child_plan_for(plan, element_rule.to)

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
                                   plan: plan, mapping: xml_mapping)
                end
              end
            end
            return xml
          end

          # Use xmlns declarations from plan
          attributes = {}

          # Apply namespace declarations from plan
          plan[:namespaces]&.each_value do |ns_config|
            next unless ns_config[:declared_at] == :here

            ns_class = ns_config[:ns_object]

            # Parse the ready-to-use declaration string
            decl = ns_config[:xmlns_declaration]
            if decl.start_with?("xmlns:")
              # Prefixed namespace: "xmlns:prefix=\"uri\""
              prefix = decl[/xmlns:(\w+)=/, 1]
              attributes["xmlns:#{prefix}"] = ns_class.uri
            else
              # Default namespace: "xmlns=\"uri\""
              attributes["xmlns"] = ns_class.uri
            end
          end

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
            value = attr.serialize(value, :xml, register) if attr
            value = ExportTransformer.call(value, attribute_rule, attr,
                                           format: :xml)
            value = value&.join(attribute_rule.delimiter) if attribute_rule.delimiter

            if attribute_rule.as_list && attribute_rule.as_list[:export]
              value = attribute_rule.as_list[:export].call(value)
            end

            if render_element?(attribute_rule, element, value)
              # Resolve attribute namespace from plan
              ns_info = resolve_attribute_namespace(attribute_rule, attr,
                                                    options.merge(mapper_class: mapper_class))
              attr_name = if ns_info[:prefix]
                            "#{ns_info[:prefix]}:#{mapping_rule_name}"
                          else
                            attribute_rule.prefixed_name
                          end
              attributes[attr_name] = value ? value.to_s : value
            end
          end

          # Add schema_location attribute from ElementNode if present
          # This is for the plan-based path where schema_location_attr is computed during planning
          attributes.merge!(plan.root_node.schema_location_attr) if plan.respond_to?(:root_node) && plan.root_node&.schema_location_attr

          # Determine prefix from plan
          prefix = nil
          option_rule = options[:rule]
          namespace_class = if option_rule&.prefix_set? || option_rule&.namespace_set?
                              option_rule.namespace_class
                            else
                              xml_mapping.namespace_class
                            end
          if namespace_class
            key = namespace_class.to_key
            ns_config = plan[:namespaces][key]

            if ns_config && ns_config[:format] == :prefix
              # Use prefix from the plan's namespace object (may be custom override)
              prefix = ns_config[:ns_object].prefix_default
            end
          end

          tag_name = options[:tag_name] || xml_mapping.root_element
          return if options[:except]&.include?(tag_name)

          xml.create_and_add_element(tag_name, prefix: prefix,
                                               attributes: attributes.compact) do
            # Call attribute custom methods now that element is created
            attribute_custom_methods.each do |attribute_rule|
              mapper_class.new.send(attribute_rule.custom_methods[:to],
                                    element, xml.parent, xml)
            end

            if ordered?(element, options.merge(mapper_class: mapper_class))
              build_ordered_element_with_plan(xml, element, plan,
                                              options.merge(mapper_class: mapper_class, parent_prefix: prefix))
            else
              build_unordered_children_with_plan(xml, element, plan,
                                                 options.merge(mapper_class: mapper_class, parent_prefix: prefix))
            end
          end
        end

        # NOTE: build_unordered_children_with_plan and build_ordered_element_with_plan
        # are inherited from BaseAdapter and use child_plan_for for unified plan access

        def handle_nested_elements_with_plan(xml, value, rule, attribute, plan,
    options)
          element_options = options.merge(
            rule: rule,
            attribute: attribute,
            tag_name: rule.name,
            mapper_class: attribute.type(register), # Override with child's type
          )

          if value.is_a?(Lutaml::Model::Collection)
            value.collection.each do |val|
              build_element_with_plan(xml, val, plan, element_options)
            end
            return
          end

          case value
          when Array
            value.each do |val|
              if plan
                build_element_with_plan(xml, val, plan, element_options)
              else
                # Fallback for cases without plan
                build_element(xml, val, element_options)
              end
            end
          else
            if plan
              build_element_with_plan(xml, value, plan, element_options)
            else
              # Fallback for cases without plan
              build_element(xml, value, element_options)
            end
          end
        end

        def add_simple_value(xml, rule, value, attribute, plan: nil,
    mapping: nil)
          # Apply value_map transformation BEFORE checking if should render
          value = rule.render_value_for(value) if rule

          # Handle array values by creating multiple elements
          if value.is_a?(Array)
            # For empty arrays, check if we should render based on render_empty option
            if value.empty?
              # Only create element if render_empty is set to render (not :omit)
              if rule.render_empty?
                # Create single empty element for the collection
                # Determine how to render based on render_empty option
                if rule.render_empty_as_nil?
                  # render_empty: :as_nil
                  xml.create_and_add_element(rule.name,
                                             attributes: { "xsi:nil" => true },
                                             prefix: nil)
                else
                  # render_empty: :as_blank or :as_empty
                  xml.create_and_add_element(rule.name,
                                             attributes: nil,
                                             prefix: nil)
                end
              end
              # Don't iterate over empty array
              return
            end

            # Non-empty array: create element for each value
            value.each do |val|
              add_simple_value(xml, rule, val, attribute, plan: plan,
                                                          mapping: mapping)
            end
            return
          end

          # Get form_default from parent's schema (namespace class)
          form_default = mapping&.namespace_class&.element_form_default || :qualified

          # Resolve element's namespace first to know which namespace we're dealing with
          temp_ns_info = rule.resolve_namespace(
            attr: attribute,
            register: register,
            parent_ns_uri: mapping&.namespace_uri,
            parent_ns_class: mapping&.namespace_class,
            form_default: form_default,
            use_prefix: false, # Temporary, just to get namespace
            parent_prefix: nil,
          )

          element_ns_uri = temp_ns_info[:uri]

          # NAMESPACE RESOLUTION: Determine if element should use prefix
          # Cases:
          # 1. namespace: :inherit → always use parent prefix
          # 2. Type namespace → use Type's namespace from plan
          # 3. Parent uses prefix format AND element has no explicit/type namespace → inherit parent
          # 4. Element has namespace matching parent → check plan[:namespaces][ns_class]
          # 5. Element has explicit namespace: nil → NO prefix ever

          use_prefix = false
          parent_prefix = nil

          # PRIORITY: Check explicit form and prefix options FIRST
          # These override all other considerations
          if rule.qualified?
            # Explicit form: :qualified - element MUST use prefix
            use_prefix = true
            # Find appropriate prefix for the element's namespace
            if element_ns_uri && plan && plan[:namespaces]
              ns_entry = plan[:namespaces].find do |_key, ns_config|
                ns_config[:ns_object].uri == element_ns_uri
              end
              if ns_entry
                _key, ns_config = ns_entry
                parent_prefix = ns_config[:ns_object].prefix_default
              end
            end
          elsif rule.unqualified?
            # Explicit form: :unqualified - element MUST NOT use prefix
            use_prefix = false
            parent_prefix = nil
          elsif rule.prefix_set?
            # Explicit prefix option - element should use specified prefix
            use_prefix = true
            # If prefix is a string, use it; if true, use namespace's default prefix
            if rule.prefix.is_a?(String)
              parent_prefix = rule.prefix
            elsif element_ns_uri && plan && plan[:namespaces]
              ns_entry = plan[:namespaces].find do |_key, ns_config|
                ns_config[:ns_object].uri == element_ns_uri
              end
              if ns_entry
                _key, ns_config = ns_entry
                parent_prefix = ns_config[:ns_object].prefix_default
              end
            end
          elsif rule.namespace_param == :inherit
            # Case 1: Explicit :inherit - always use parent format
            use_prefix = true
            if plan && mapping&.namespace_class
              key = mapping.namespace_class.to_key
              ns_config = plan[:namespaces][key]
              if ns_config && ns_config[:format] == :prefix
                # CRITICAL: Use the ns_object from plan (may be override with custom prefix)
                parent_prefix = ns_config[:ns_object].prefix_default
              end
            end
          elsif plan && plan[:type_namespaces] && plan[:type_namespaces][rule.to]
            # Case 2: Type namespace - this attribute's type defines its own namespace
            # Priority: Type namespace takes precedence over parent inheritance
            type_ns_class = plan[:type_namespaces][rule.to]
            key = type_ns_class.to_key
            ns_config = plan[:namespaces][key]
            if ns_config && ns_config[:format] == :prefix
              use_prefix = true
              # CRITICAL: Use ns_object from plan (may be override with custom prefix)
              parent_prefix = ns_config[:ns_object].prefix_default
            end
          elsif !rule.namespace_set? && !element_ns_uri && mapping&.namespace_class && plan
            # Case 3: NEW - Format Matching Rule
            # When parent uses prefix format AND element has no explicit namespace AND no type namespace,
            # element inherits parent's namespace and prefix for consistent formatting.
            # This handles the test case where children should match parent's serialization format.
            # IMPORTANT: Only applies when element_form_default is :qualified
            key = mapping.namespace_class.to_key
            ns_config = plan[:namespaces][key]
            if ns_config && ns_config[:format] == :prefix && form_default == :qualified
              # Parent is using prefix format AND schema requires qualified elements
              use_prefix = true
              parent_prefix = ns_config[:ns_object].prefix_default
              # Override element_ns_uri to parent's URI for proper resolution
              element_ns_uri = mapping.namespace_uri
            end
          elsif element_ns_uri
            # Case 4: Element has explicit namespace - check if it's in prefix mode
            # Need to find the namespace class by URI to look up config
            if plan && plan[:namespaces]
              # Find namespace entry that matches this URI
              ns_entry = plan[:namespaces].find do |_key, ns_config|
                ns_config[:ns_object].uri == element_ns_uri
              end
              if ns_entry
                _key, ns_config = ns_entry
                use_prefix = ns_config[:format] == :prefix
                parent_prefix = ns_config[:ns_object].prefix_default if use_prefix
              end
            end
          elsif !rule.namespace_set? && element_ns_uri && element_ns_uri == mapping&.namespace_uri
            # Case 5: Element has SAME namespace as parent (not nil, not unqualified)
            # Element has a resolved namespace that matches parent -> inherit parent format
            # Truly unqualified elements (element_ns_uri.nil?) do NOT inherit
            if plan && mapping&.namespace_class
              key = mapping.namespace_class.to_key
              ns_config = plan[:namespaces][key]
              if ns_config && ns_config[:format] == :prefix
                use_prefix = true
                # CRITICAL: Use the ns_object from plan (may be override with custom prefix)
                parent_prefix = ns_config[:ns_object].prefix_default
              end
            end
          end
          # Case 6: explicit namespace: nil is handled by namespace_set? && namespace_param == nil
          # Case 7: truly unqualified (element_ns_uri.nil?) falls through with use_prefix = false

          # Now resolve with correct use_prefix
          ns_info = rule.resolve_namespace(
            attr: attribute,
            register: register,
            parent_ns_uri: mapping&.namespace_uri,
            parent_ns_class: mapping&.namespace_class,
            form_default: form_default,
            use_prefix: use_prefix,
            parent_prefix: parent_prefix,
          )

          # Use resolved namespace directly, BUT handle special cases:
          # 1. namespace: :inherit → ALWAYS use parent prefix (resolved has parent URI)
          # 2. Truly unqualified elements (element_ns_uri==nil) → NO prefix unless :inherit
          resolved_prefix = if rule.namespace_param == :inherit || (use_prefix && parent_prefix)
                              parent_prefix
                            else
                              ns_info[:prefix]
                            end

          # Prepare attributes (no xmlns declaration - handled by DeclarationPlanner)
          attributes = {}

          # Check if this namespace needs local declaration (out of scope)
          if resolved_prefix && plan && plan[:namespaces]
            # Find the namespace config for this prefix/URI
            ns_entry = plan[:namespaces].find do |_key, ns_config|
              ns_config[:ns_object].prefix_default == resolved_prefix ||
                (ns_info[:uri] && ns_config[:ns_object].uri == ns_info[:uri])
            end

            if ns_entry
              _key, ns_config = ns_entry
              # If namespace is marked for local declaration, add xmlns attribute
              if ns_config[:declared_at] == :local_on_use
                xmlns_attr = "xmlns:#{resolved_prefix}"
                attributes[xmlns_attr] = ns_config[:ns_object].uri
              end
            end
          end

          if value.nil?
            # Check render_nil option to determine how to render nil value
            if rule.render_nil_as_blank? || rule.render_nil_as_empty?
              # render_nil: :as_blank or :as_empty - create blank element without xsi:nil
              xml.create_and_add_element(rule.name,
                                         attributes: attributes,
                                         prefix: resolved_prefix)
            else
              # render_nil: :as_nil or default - create element with xsi:nil="true"
              xml.create_and_add_element(rule.name,
                                         attributes: attributes.merge({ "xsi:nil" => true }),
                                         prefix: resolved_prefix)
            end
          elsif ::Lutaml::Model::Utils.uninitialized?(value)
            # Handle uninitialized values - don't try to serialize them as text
            # This should not normally happen as render? should filter these out
            # But if render_omitted is set, we might reach here
            nil
          elsif ::Lutaml::Model::Utils.empty?(value)
            xml.create_and_add_element(rule.name,
                                       attributes: attributes,
                                       prefix: resolved_prefix)
          elsif rule.raw_mapping?
            xml.add_xml_fragment(xml, value)
          elsif value.is_a?(::Hash) && attribute&.type(register) == Lutaml::Model::Type::Hash
            # Check if value is Hash type that needs wrapper - do this BEFORE any wrapping/serialization
            # Value is already transformed by ExportTransformer before reaching here
            xml.create_and_add_element(rule.name,
                                       attributes: attributes,
                                       prefix: resolved_prefix) do
              value.each do |key, val|
                xml.create_and_add_element(key.to_s) do
                  xml.add_text(xml, val.to_s)
                end
              end
            end
          else
            xml.create_and_add_element(rule.name,
                                       attributes: attributes,
                                       prefix: resolved_prefix) do
              add_value(xml, value, attribute, cdata: rule.cdata)
            end
          end
        end

        # Build XML from XmlElement structure
        #
        # @param xml [Builder] the XML builder

        private

        def determine_encoding(options)
          options[:encoding] ||
            options[:parse_encoding] ||
            @encoding ||
            "UTF-8"
        end

        def build_ordered_element(builder, element, options = {})
          mapper_class = determine_mapper_class(element, options)
          xml_mapping = mapper_class.mappings_for(:xml)
          return builder unless xml_mapping

          attributes = build_attributes(element, xml_mapping, options).compact
          prefix = determine_namespace_prefix(options, xml_mapping)
          prefixed_xml = builder.add_namespace_prefix(prefix)
          tag_name = options[:tag_name] || xml_mapping.root_element

          prefixed_xml.create_and_add_element(tag_name,
                                              attributes: attributes) do |el|
            process_element_order(el, element, xml_mapping, mapper_class,
                                  options)
          end
        end

        def process_element_order(builder, element, xml_mapping, mapper_class,
    options)
          index_hash = {}
          content = []

          element.element_order.each do |object|
            process_ordered_object(builder, element, object, xml_mapping, mapper_class,
                                   index_hash, content, options)
          end

          builder.add_text(builder, content.join)
        end

        def process_ordered_object(builder, element, object, xml_mapping, mapper_class,
                                  index_hash, content, options)
          curr_index = increment_object_index(index_hash, object)
          element_rule = xml_mapping.find_by_name(object.name,
                                                  type: object.type,
                                                  node_type: object.node_type)

          return if skip_element_rule?(element_rule, options)

          attribute_def = attribute_definition_for(element, element_rule,
                                                   mapper_class: mapper_class)
          value = attribute_value_for(element, element_rule)

          return if skip_cdata_text?(element_rule, xml_mapping, object)

          handle_ordered_element_content(builder, element, element_rule, xml_mapping,
                                         attribute_def, value, curr_index, content, options, mapper_class)
        end

        def increment_object_index(index_hash, object)
          object_key = "#{object.name}-#{object.type}"
          index_hash[object_key] ||= -1
          index_hash[object_key] += 1
        end

        def skip_element_rule?(element_rule, options)
          element_rule.nil? || options[:except]&.include?(element_rule.to)
        end

        def skip_cdata_text?(element_rule, xml_mapping, object)
          element_rule == xml_mapping.content_mapping && element_rule.cdata && object.text?
        end

        def handle_ordered_element_content(builder, element, element_rule, xml_mapping,
                                          attribute_def, value, curr_index, content, options, mapper_class)
          if element_rule == xml_mapping.content_mapping
            handle_ordered_content_text(builder, element, element_rule,
                                        xml_mapping, curr_index, content)
          elsif !value.nil? || element_rule.render_nil?
            add_ordered_element_value(builder, element, attribute_def, value, curr_index,
                                      element_rule, options, mapper_class)
          end
        end

        def handle_ordered_content_text(builder, element, element_rule,
    xml_mapping, curr_index, content)
          text = xml_mapping.content_mapping.serialize(element)
          text = text[curr_index] if text.is_a?(Array)

          if element.mixed?
            return builder.add_text(builder, text,
                                    cdata: element_rule.cdata)
          end

          content << text
        end

        def add_ordered_element_value(builder, element, attribute_def, value, curr_index,
                                     element_rule, options, mapper_class)
          value = value[curr_index] if attribute_def.collection?

          add_to_xml(builder, element, nil, value,
                     options.merge(attribute: attribute_def, rule: element_rule,
                                   mapper_class: mapper_class))
        end
      end
    end
  end
end
