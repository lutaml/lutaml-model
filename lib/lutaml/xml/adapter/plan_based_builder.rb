# frozen_string_literal: true

module Lutaml
  module Xml
    module Adapter
      # Builds XML elements from model instances using namespace declaration plans.
      #
      # Handles both ordered and unordered child serialization, nested model
      # elements, simple values, and namespace resolution. This module is the
      # core of model-to-XML conversion when a DeclarationPlan drives the output.
      module PlanBasedBuilder
        # Build element using prepared namespace declaration plan
        #
        # @param xml [Builder] the XML builder
        # @param element [Object] the model instance
        # @param plan [DeclarationPlan] the declaration plan from DeclarationPlanner
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
            build_type_only_element(xml, element, xml_mapping, plan, options,
                                    mapper_class)
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
              apply_custom_to(attribute_rule, element, inner_xml, mapper_class)
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
                            # Same namespace + unqualified -> NO prefix (W3C rule)
                            attr.name
                          else
                            # Different namespace OR qualified -> use prefix
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
            attributes["xmlns"] = ""
          elsif !plan
            # Fallback logic when no plan is available
            if parent_uses_default_ns
              if parent_element_form_default == :qualified
                # Child should INHERIT parent's namespace - no xmlns="" needed
              else
                # Parent's element_form_default is :unqualified - child in blank namespace
                attributes["xmlns"] = ""
              end
            end
          end

          # Check if element was created from nil value with render_nil option
          if element.is_a?(Lutaml::Xml::DataModel::XmlElement) && element.xsi_nil
            attributes["xsi:nil"] = true
          end

          # Create element
          xml.create_and_add_element(tag_name, attributes: attributes,
                                               prefix: prefix) do |inner_xml|
            # Handle raw content (map_all directive)
            has_raw_content = false
            if element.is_a?(Lutaml::Xml::DataModel::XmlElement)
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
                case child
                when Lutaml::Xml::DataModel::XmlElement
                  build_xml_element(inner_xml, child,
                                    parent_uses_default_ns: this_element_uses_default_ns,
                                    parent_element_form_default: this_element_form_default,
                                    parent_namespace_class: element_ns_class,
                                    plan: plan,
                                    xml_mapping: xml_mapping)
                when Lutaml::Xml::DataModel::XmlComment
                  inner_xml.add_comment(child.content)
                when Lutaml::Xml::DataModel::XmlRawFragment
                  inner_xml.add_xml_fragment(inner_xml, child.content)
                when String
                  if element.cdata
                    inner_xml.cdata(child.to_s)
                  else
                    inner_xml.text(text_content_for_xml(child))
                  end
                end
              end
            end
          end
        end

        # Build unordered child elements using prepared namespace declaration plan
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
              apply_custom_to(element_rule, element, xml, mapper_class)
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
              apply_custom_to(element_rule, element, xml, mapper_class)
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

        def build_type_only_element(xml, element, xml_mapping, plan, options,
    mapper_class)
          if options[:tag_name]
            xml.create_and_add_element(options[:tag_name]) do |inner_xml|
              # Serialize type-only model's children inside parent's wrapper
              xml_mapping.elements.each do |element_rule|
                next if options[:except]&.include?(element_rule.to)

                attribute_def = mapper_class.attributes[element_rule.to]
                next unless attribute_def

                value = element.public_send(element_rule.to)
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

              value = element.public_send(element_rule.to)
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
            build_collection_elements(xml, value, attribute, rule,
                                      element_options, parent_plan, options)
            return
          end

          case value
          when Array
            build_array_elements(xml, value, attribute, rule, element_options,
                                 plan, parent_plan, options)
          else
            build_element_with_plan(xml, value, plan, element_options)
          end
        end

        def build_collection_elements(xml, value, attribute, rule,
    element_options, parent_plan, options)
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
              item_plan = plan_for_collection_item(val, attribute, parent_plan,
                                                   options)
              item_mapper_class = if polymorphic_value?(attribute, val)
                                    val.class
                                  else
                                    attribute.type(register)
                                  end
              item_options = element_options.merge(mapper_class: item_mapper_class)
              build_element_with_plan(xml, val, item_plan, item_options)
            end
          end
        end

        def build_array_elements(xml, value, attribute, _rule, element_options,
    _plan, parent_plan, options)
          value.each do |val|
            item_mapper_class = if polymorphic_value?(attribute, val)
                                  val.class
                                else
                                  attribute.type(register)
                                end

            item_plan = plan_for_collection_item(val, attribute, parent_plan,
                                                 options)
            item_options = element_options.merge(mapper_class: item_mapper_class)
            build_element_with_plan(xml, val,
                                    item_plan || DeclarationPlan.empty, item_options)
          end
        end

        def plan_for_collection_item(val, attribute, parent_plan, options)
          item_mapper_class = if polymorphic_value?(attribute, val)
                                val.class
                              else
                                attribute.type(register)
                              end

          item_mapping = item_mapper_class.mappings_for(:xml)
          return nil unless item_mapping

          # Transform model to XmlElement tree
          transformation = item_mapper_class.transformation_for(:xml, register)
          xml_element = transformation.transform(val, options)

          # Collect namespace needs from XmlElement tree
          collector = NamespaceCollector.new(register)
          item_needs = collector.collect(xml_element, item_mapping,
                                         mapper_class: item_mapper_class)

          # Plan with XmlElement tree (not model instance)
          planner = DeclarationPlanner.new(register)
          planner.plan(xml_element, item_mapping, item_needs,
                       parent_plan: parent_plan, options: options)
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

          resolved_prefix, attributes = resolve_simple_value_namespace(
            rule, attribute, mapping, plan, options
          )

          render_simple_value_element(xml, rule, value, attribute,
                                      resolved_prefix, attributes)
        end

        def resolve_simple_value_namespace(rule, attribute, mapping, plan,
    options)
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
          type_ns_class = if attribute && !rule.namespace_set?
                            type_class = attribute.type(register)
                            type_class.namespace_class if type_class.is_a?(Class) && type_class <= Lutaml::Model::Type::Value
                          end

          format_from_stored_plan = false

          if type_ns_class
            check_plan = plan || options[:stored_xml_declaration_plan]
            if check_plan
              stored_ns_decl = check_plan.namespaces.values.find do |decl|
                decl.uri == type_ns_class.uri
              end
              if stored_ns_decl
                resolved_prefix = if stored_ns_decl.local_on_use? || stored_ns_decl.prefix_format?
                                    stored_ns_decl.prefix
                                  end
                format_from_stored_plan = true
              end
            end
          end

          # BUG FIX #49: Check if child element is in same namespace as parent
          unless format_from_stored_plan
            element_has_no_explicit_ns = !rule.namespace_set?
            type_class = attribute&.type(register)
            type_has_no_ns = !(type_class.is_a?(Class) && type_class <= Lutaml::Model::Type::Value) ||
              !type_class&.namespace_class

            parent_ns_class = options[:parent_namespace_class]
            parent_ns_decl = options[:parent_ns_decl]
            parent_ns_uri = parent_ns_class&.uri
            child_ns_uri = ns_result[:uri]

            resolved_prefix = if element_has_no_explicit_ns && type_has_no_ns
                                nil
                              elsif parent_ns_class && parent_ns_decl &&
                                  child_ns_uri && parent_ns_uri &&
                                  child_ns_uri == parent_ns_uri
                                if parent_ns_decl.prefix_format?
                                  parent_ns_decl.prefix
                                end
                              else
                                ns_result[:prefix]
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

          [resolved_prefix, attributes]
        end

        def render_simple_value_element(xml, rule, value, attribute,
    resolved_prefix, attributes)
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
          elsif rule.raw_mapping? || rule.raw == :element
            xml.add_xml_fragment(xml, value)
          elsif value.is_a?(::Hash) && attribute&.type(register) == Lutaml::Model::Type::Hash
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

        # Get child plan from parent plan
        #
        # @param plan [DeclarationPlan, nil] the parent plan
        # @param attr_name [Symbol] the attribute name
        # @return [DeclarationPlan, nil] the child plan or nil
        def child_plan_for(plan, attr_name)
          plan&.child_plan(attr_name)
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
            delegate_obj = element.public_send(element_rule.delegate)
            if delegate_obj.is_a?(Lutaml::Model::Serialize) && delegate_obj.class.attributes.key?(element_rule.to)
              attribute_def = delegate_obj.class.attributes[element_rule.to]
              value = delegate_obj.public_send(element_rule.to)
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
          text = element.public_send(xml_mapping.content_mapping.to)
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
        def add_mixed_element(xml, element_rule, value, _attribute,
                              plan: nil, mapping: nil) # rubocop:disable Lint/UnusedMethodArgument
          xml.create_and_add_element(element_rule.name) do |child_element|
            child_element.text(value.to_s) unless ::Lutaml::Model::Utils.empty?(value)
          end
        end

        # Add accumulated content (can be overridden by adapters)
        #
        # @param xml [Builder] the XML builder
        # @param content [Array<String>] accumulated content strings
        def add_ordered_content(xml, content)
          xml.add_text(xml, content.join)
        end
      end
    end
  end
end
