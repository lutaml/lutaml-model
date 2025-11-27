require "nokogiri"
require_relative "document"
require_relative "builder/nokogiri"
require_relative "namespace_collector"
require_relative "declaration_planner"

module Lutaml
  module Model
    module Xml
      class NokogiriAdapter < Document
        def self.parse(xml, options = {})
          parsed = Nokogiri::XML(xml, nil, encoding(xml, options))
          @root = NokogiriElement.new(parsed.root)
          new(@root, parsed.encoding)
        end

        def to_xml(options = {})
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
              root.build_xml(xml)
            else
              # THREE-PHASE ARCHITECTURE
              mapper_class = options[:mapper_class] || @root.class
              xml_mapping = mapper_class.mappings_for(:xml)

              # Phase 1: Collect namespace needs
              collector = NamespaceCollector.new(register)
              needs = collector.collect(@root, xml_mapping)

              # Phase 2: Plan declarations
              planner = DeclarationPlanner.new(register)
              plan = planner.plan(@root, xml_mapping, needs, options: options)

              # Phase 3: Build with plan
              build_element_with_plan(xml, @root, plan, options)
            end
          end

          xml_options = {}
          if options[:pretty]
            xml_options[:indent] = 2
          end

          xml_data = builder.doc.root.to_xml(xml_options)
          options[:declaration] ? declaration(options) + xml_data : xml_data
        end

        # Build element using prepared namespace declaration plan
        #
        # @param xml [Builder] the XML builder
        # @param element [Object] the model instance
        # @param plan [Hash] the declaration plan from DeclarationPlanner
        # @param options [Hash] serialization options
        def build_element_with_plan(xml, element, plan, options = {})
          # Provide default empty plan if nil (e.g., for custom methods)
          plan ||= {
            namespaces: {},
            children_plans: {},
            type_namespaces: {},
          }

          mapper_class = options[:mapper_class] || element.class

          # NEW: Handle simple types that don't have mappings
          unless mapper_class.respond_to?(:mappings_for)
            tag_name = options[:tag_name] || "element"
            xml.create_and_add_element(tag_name) do |inner_xml|
              inner_xml.text(element.to_s)
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
                    child_plan = plan[:children_plans][element_rule.to] || {
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

                child_plan = plan[:children_plans][element_rule.to]

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

          # Add schema location if present
          if element.respond_to?(:schema_location) &&
              element.schema_location.is_a?(Lutaml::Model::SchemaLocation) &&
              !options[:except]&.include?(:schema_location)
            attributes.merge!(element.schema_location.to_xml_attributes)
          end

          # Determine prefix from plan
          prefix = nil
          if xml_mapping.namespace_class
            key = xml_mapping.namespace_class.to_key
            ns_config = plan[:namespaces][key]

            if ns_config && ns_config[:format] == :prefix
              # Use prefix from the plan's namespace object (may be custom override)
              prefix = ns_config[:ns_object].prefix_default
            end
          end

          tag_name = options[:tag_name] || xml_mapping.root_element
          return if options[:except]&.include?(tag_name)

          xml.create_and_add_element(tag_name, attributes: attributes,
                                               prefix: prefix) do
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

        def build_unordered_children_with_plan(xml, element, plan, options)
          mapper_class = options[:mapper_class] || element.class
          xml_mapping = mapper_class.mappings_for(:xml)

          # Process child elements with their plans (INCLUDING raw_mapping for map_all)
          mappings = xml_mapping.elements + [xml_mapping.raw_mapping].compact
          mappings.each do |element_rule|
            next if options[:except]&.include?(element_rule.to)

            # Handle custom methods
            if element_rule.custom_methods[:to]
              mapper_class.new.send(element_rule.custom_methods[:to], element,
                                    xml.parent, xml)
              next
            end

            attribute_def = mapper_class.attributes[element_rule.to]

            # For delegated attributes, attribute_def might be nil since the attribute
            # doesn't exist directly on the main class (e.g., :color doesn't exist on Ceramic,
            # it exists on the delegated :glaze object)
            next unless attribute_def || element_rule.delegate

            # Handle delegation - if rule has delegate option, get value from delegated object
            value = nil
            if element_rule.delegate
              # Get the delegated object
              delegate_obj = element.send(element_rule.delegate)
              if delegate_obj.respond_to?(element_rule.to)
                value = delegate_obj.send(element_rule.to)
              end

            else
              # Use safe attribute access for non-delegated attributes
              value = if element.respond_to?(element_rule.to)
                        element.send(element_rule.to)
                      end
            end

            next unless element_rule.render?(value, element)

            # Get child's plan if available
            child_plan = plan[:children_plans][element_rule.to]

            # NEW: Check if value is a Collection instance
            is_collection_instance = value.is_a?(Lutaml::Model::Collection)

            if value && (attribute_def&.type(register)&.<=(Lutaml::Model::Serialize) || is_collection_instance)
              handle_nested_elements_with_plan(
                xml,
                value,
                element_rule,
                attribute_def,
                child_plan,
                options,
              )
            else
              # Apply transformations BEFORE adding to XML
              if attribute_def
                value = ExportTransformer.call(value, element_rule,
                                               attribute_def, format: :xml)
              end
              # Handle non-model values (strings, etc.)
              if element_rule.delegate && attribute_def.nil?
                add_simple_value(xml, element_rule, value, nil, plan: plan,
                                                                mapping: xml_mapping)
              else
                add_simple_value(xml, element_rule, value, attribute_def,
                                 plan: plan, mapping: xml_mapping)
              end
            end
          end

          # Process content mapping
          process_content_mapping(element, xml_mapping.content_mapping,
                                  xml, mapper_class)
        end

        def build_ordered_element_with_plan(xml, element, plan, options)
          mapper_class = options[:mapper_class] || element.class
          xml_mapping = mapper_class.mappings_for(:xml)

          index_hash = ::Hash.new { |key, value| key[value] = -1 }
          content = []

          element.element_order.each do |object|
            object_key = "#{object.name}-#{object.type}"
            curr_index = index_hash[object_key] += 1

            element_rule = xml_mapping.find_by_name(object.name,
                                                    type: object.type)
            next if element_rule.nil? || options[:except]&.include?(element_rule.to)

            # Handle custom methods
            if element_rule.custom_methods[:to]
              # Custom methods usually handle their own iteration/logic, but here we are inside an ordered loop.
              # If the custom method handles the whole attribute, we might be calling it multiple times if we are not careful.
              # However, element_order usually contains individual items for mixed content.
              # For non-mixed ordered content, it might contain the attribute name.

              # If it's a custom method, we delegate and hope it handles the current context or value correctly.
              # But wait, custom methods usually take the whole model.
              # If we are iterating element_order, we might be looking at specific values.

              # For now, let's assume custom methods are not used with mixed content in a way that breaks this,
              # or that they handle the specific value if we could pass it.
              # But the signature is (model, parent, doc).

              # If we call it here, it might render ALL values of that attribute.
              # This is tricky for ordered content if the attribute has multiple values interspersed with others.

              # If custom method is used, maybe we should skip it in element_order loop and rely on it being called?
              # But then order is lost.

              # Let's assume for now custom methods are compatible with standard rendering or not used in mixed/ordered complex scenarios.
              # Or we call it once and track it?

              # Re-reading Document#build_ordered_element:
              # It calls add_to_xml. add_to_xml handles custom_methods.
              # So yes, it calls custom method.

              mapper_class.new.send(element_rule.custom_methods[:to], element,
                                    xml.parent, xml)
              next
            end

            # Handle delegation - get attribute definition and value from delegated object
            attribute_def = nil
            value = nil

            if element_rule.delegate
              # Get the delegated object
              delegate_obj = element.send(element_rule.delegate)
              if delegate_obj.respond_to?(element_rule.to)
                # Get attribute definition from delegated object's class
                attribute_def = delegate_obj.class.attributes[element_rule.to]
                # Get value from delegated object
                value = delegate_obj.send(element_rule.to)
              end

            else
              # Normal (non-delegated) attribute handling
              attribute_def = mapper_class.attributes[element_rule.to]
              value = if element.respond_to?(element_rule.to)
                        element.send(element_rule.to)
                      end
            end

            if element_rule == xml_mapping.content_mapping
              next if element_rule.cdata && object.text?

              text = xml_mapping.content_mapping.serialize(element)
              text = text[curr_index] if text.is_a?(Array)

              if element.mixed?
                xml.add_text(xml.parent, text, cdata: element_rule.cdata)
                next
              end

              content << text
            elsif !value.nil? || element_rule.render_nil?
              # Handle collection values by index
              current_value = if attribute_def&.collection? && value.is_a?(Array)
                                value[curr_index]
                              elsif attribute_def&.collection? && value.is_a?(Lutaml::Model::Collection)
                                value.to_a[curr_index]
                              else
                                value
                              end

              # Get child's plan if available
              child_plan = plan[:children_plans][element_rule.to]

              is_collection_instance = current_value.is_a?(Lutaml::Model::Collection)

              if current_value && (attribute_def&.type(register)&.<=(Lutaml::Model::Serialize) || is_collection_instance)
                handle_nested_elements_with_plan(
                  xml,
                  current_value,
                  element_rule,
                  attribute_def,
                  child_plan,
                  options,
                )
              else
                # Apply transformations if attribute_def exists
                if attribute_def
                  current_value = ExportTransformer.call(current_value,
                                                         element_rule, attribute_def, format: :xml)
                end

                add_simple_value(xml, element_rule, current_value, attribute_def,
                                 plan: plan, mapping: xml_mapping)
              end
            end
          end

          unless content.empty?
            xml.text content.join
          end
        end

        # Handle nested model elements with plan
        def handle_nested_elements_with_plan(xml, value, rule, attribute,
child_plan, options)
          element_options = options.merge(
            rule: rule,
            attribute: attribute,
            tag_name: rule.name,
            mapper_class: attribute.type(register), # Override with child's type
          )

          # CRITICAL FIX: For wrappers (like CurveArrayProperty),
          # child_plan is the plan for the wrapper, which contains children_plans for the actual items.
          # When serializing the wrapper, we'll recursively call build_element_with_plan,
          # which will use child_plan[:children_plans] to find plans for the wrapper's children.
          # So we don't need special logic here - just pass child_plan as-is.

          if value.is_a?(Lutaml::Model::Collection)
            value.collection.each do |val|
              # For polymorphic collections, use each item's actual class
              # Check both attribute polymorphic flag and value's class polymorphic markers
              item_mapper_class = if polymorphic_value?(attribute, val)
                                    val.class
                                  else
                                    attribute.type(register)
                                  end
              item_options = element_options.merge(mapper_class: item_mapper_class)
              build_element_with_plan(xml, val, child_plan, item_options)
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
              item_options = element_options.merge(mapper_class: item_mapper_class)
              build_element_with_plan(xml, val, child_plan, item_options)
            end
          else
            # For single polymorphic values, use the value's actual class
            if polymorphic_value?(attribute, value)
              element_options = element_options.merge(mapper_class: value.class)
            end
            build_element_with_plan(xml, value, child_plan, element_options)
          end
        end

        def polymorphic_value?(attribute, value)
          return false unless attribute
          return false unless value.respond_to?(:class)

          # Check if attribute explicitly declares polymorphism
          return true if attribute.options[:polymorphic] || attribute.polymorphic?

          # Check if value's class is part of a polymorphic hierarchy
          # (has an attribute with polymorphic_class: true)
          value_class = value.class
          return false unless value_class.respond_to?(:attributes)

          value_class.attributes.values.any?(&:polymorphic?)
        end

        # Add simple (non-model) values to XML
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
          # Case 5: explicit namespace: nil is handled by namespace_set? && namespace_param == nil
          # Case 6: truly unqualified (element_ns_uri.nil?) falls through with use_prefix = false

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
          resolved_prefix = if rule.namespace_param == :inherit
                              # Explicit :inherit - always use parent's prefix
                              parent_prefix
                            elsif use_prefix && parent_prefix
                              # Element has same namespace as parent and parent uses prefix
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
                                         attributes: attributes.empty? ? nil : attributes,
                                         prefix: resolved_prefix)
            else
              # render_nil: :as_nil or default - create element with xsi:nil="true"
              xml.create_and_add_element(rule.name,
                                         attributes: attributes.merge({ "xsi:nil" => true }),
                                         prefix: resolved_prefix)
            end
          elsif Utils.uninitialized?(value)
            # Handle uninitialized values - don't try to serialize them as text
            # This should not normally happen as render? should filter these out
            # But if render_omitted is set, we might reach here
            nil
          elsif Utils.empty?(value)
            xml.create_and_add_element(rule.name,
                                       attributes: attributes.empty? ? nil : attributes,
                                       prefix: resolved_prefix)
          elsif rule.raw_mapping?
            xml.add_xml_fragment(xml, value)
          elsif value.is_a?(::Hash) && attribute&.type(register) == Lutaml::Model::Type::Hash
            # Check if value is Hash type that needs wrapper - do this BEFORE any wrapping/serialization
            # Value is already transformed by ExportTransformer before reaching here
            xml.create_and_add_element(rule.name,
                                       attributes: attributes.empty? ? nil : attributes,
                                       prefix: resolved_prefix) do
              value.each do |key, val|
                xml.create_and_add_element(key.to_s) do
                  xml.text(val.to_s)
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

        private

        def prefix_xml(xml, mapping, options)
          if options.key?(:namespace_prefix)
            xml[options[:namespace_prefix]] if options[:namespace_prefix]
          elsif mapping.namespace_prefix
            xml[mapping.namespace_prefix]
          end
          xml
        end
      end

      class NokogiriElement < XmlElement
        def initialize(node, root_node: nil, default_namespace: nil)
          if root_node
            node.namespaces.each do |prefix, name|
              namespace = XmlNamespace.new(name, prefix)

              root_node.add_namespace(namespace)
            end
          end

          attributes = {}

          # Using `attribute_nodes` instead of `attributes` because
          # `attribute_nodes` handles name collisions as well
          # More info: https://devdocs.io/nokogiri/nokogiri/xml/node#method-i-attributes
          node.attribute_nodes.each do |attr|
            name = if attr.namespace
                     "#{attr.namespace.prefix}:#{attr.name}"
                   else
                     attr.name
                   end

            attributes[name] = XmlAttribute.new(
              name,
              attr.value,
              namespace: attr.namespace&.href,
              namespace_prefix: attr.namespace&.prefix,
            )
          end

          # Detect if xmlns="" is explicitly set (explicit no namespace)
          # Use shared helper method for consistency across all adapters
          explicit_no_namespace = XmlElement.detect_explicit_no_namespace(
            has_empty_xmlns: node.namespaces.key?("xmlns") && node.namespaces["xmlns"] == "",
            node_namespace_nil: node.namespace.nil?
          )

          # Set default namespace for root, or inherit from parent for children
          if !node.namespace&.prefix
            default_namespace = node.namespace&.href ||
              root_node&.instance_variable_get(:@default_namespace)
          end

          super(
            node,
            attributes,
            parse_all_children(node, root_node: root_node || self,
                                     default_namespace: default_namespace),
            node.text,
            name: node.name,
            parent_document: root_node,
            namespace_prefix: node.namespace&.prefix,
            default_namespace: default_namespace,
            explicit_no_namespace: explicit_no_namespace
          )
        end

        def text?
          # false
          children.empty? && text.length.positive?
        end

        def to_xml
          return text if text?

          build_xml.doc.root.to_xml
        end

        def inner_xml
          children.map(&:to_xml).join
        end

        def build_xml(builder = nil)
          builder ||= Builder::Nokogiri.build

          if name == "text"
            builder.text(text)
          else
            builder.public_send(name, build_attributes(self)) do |xml|
              children.each do |child|
                child.build_xml(xml)
              end
            end
          end

          builder
        end

        private

        def parse_children(node, root_node: nil)
          node.children.select(&:element?).map do |child|
            NokogiriElement.new(child, root_node: root_node)
          end
        end

        def parse_all_children(node, root_node: nil, default_namespace: nil)
          node.children.map do |child|
            NokogiriElement.new(child, root_node: root_node,
                                       default_namespace: default_namespace)
          end
        end

        def build_attributes(node, _options = {})
          attrs = node.attributes.transform_values(&:value)

          attrs.merge(build_namespace_attributes(node))
        end

        def build_namespace_attributes(node)
          namespace_attrs = {}

          node.own_namespaces.each_value do |namespace|
            namespace_attrs[namespace.attr_name] = namespace.uri
          end

          node.children.each do |child|
            namespace_attrs = namespace_attrs.merge(
              build_namespace_attributes(child),
            )
          end

          namespace_attrs
        end
      end
    end
  end
end
