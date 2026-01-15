require "ox"
require_relative "document"
require_relative "builder/ox"
require_relative "namespace_collector"
require_relative "declaration_planner"
require_relative "namespace_resolver"
require_relative "declaration_handler"
require_relative "input_namespace_extractor"
require_relative "polymorphic_value_handler"
require_relative "doctype_extractor"
require_relative "namespace_declaration_builder"
require_relative "attribute_namespace_resolver"
require_relative "element_prefix_resolver"
require_relative "ox/element"
require_relative "declaration_plan_query"

module Lutaml
  module Model
    module Xml
      class OxAdapter < Document
        include DeclarationHandler
        include PolymorphicValueHandler
        extend DocTypeExtractor

        def self.parse(xml, options = {})
          Ox.default_options = Ox.default_options.merge(encoding: encoding(xml,
                                                                           options))

          parsed = Ox.parse(xml)
          # Ox.parse returns Ox::Document if XML has declaration, Ox::Element otherwise
          # Skip Ox::DocType nodes to get the actual root element
          root_element = if parsed.is_a?(::Ox::Document)
                          parsed.nodes.find { |node| node.is_a?(::Ox::Element) }
                        else
                          parsed
                        end

          # Extract DOCTYPE information if present
          # Ox doesn't directly expose DOCTYPE, so we need to parse it from the original XML
          doctype_info = extract_doctype_from_xml(xml)

          # Extract input namespace declarations for Issue #3: Namespace Preservation
          input_namespaces = InputNamespaceExtractor.extract(root_element, :ox)

          @root = OxElement.new(root_element)
          new(@root, Ox.default_options[:encoding], doctype: doctype_info,
              input_namespaces: input_namespaces)
        end

        def to_xml(options = {})
          # Accept xml_declaration from options if present (for model serialization)
          @xml_declaration = options[:xml_declaration] if options[:xml_declaration]

          # Accept input_namespaces from options if present (for namespace format preservation)
          @input_namespaces = options[:input_namespaces] if options[:input_namespaces]

          builder = Builder::Ox.build()
          builder_options = { version: options[:version] }

          builder_options[:encoding] = if options.key?(:encoding)
                                         options[:encoding] unless options[:encoding].nil?
                                       elsif options.key?(:parse_encoding)
                                         options[:parse_encoding]
                                       else
                                         "UTF-8"
                                       end

          builder.xml.instruct(:xml, encoding: builder_options[:encoding])

          if @root.is_a?(Lutaml::Model::Xml::OxElement)
            @root.build_xml(builder)
          elsif @root.is_a?(Lutaml::Model::XmlDataModel::XmlElement)
            # XmlDataModel MUST go through Three-Phase Architecture
            mapper_class = options[:mapper_class] || @root.class
            xml_mapping = mapper_class.mappings_for(:xml)

            # Phase 1: Collect namespace needs from XmlElement tree
            collector = NamespaceCollector.new(register)
            needs = collector.collect(@root, xml_mapping)

            # Phase 2: Plan namespace declarations with hoisting
            planner = DeclarationPlanner.new(register)
            plan_options = options.merge(input_namespaces: @input_namespaces)
            plan = planner.plan(@root, xml_mapping, needs, options: plan_options)

            # Phase 3: Build XmlElement structure (NOT model instance)
            build_xml_element(builder, @root, plan: plan, xml_mapping: xml_mapping)
          else
            # THREE-PHASE ARCHITECTURE
            mapper_class = options[:mapper_class] || @root.class
            xml_mapping = mapper_class.mappings_for(:xml)

            # Check if model has map_all with custom methods
            # Custom methods work with model instances, not XmlElement trees
            has_custom_map_all = xml_mapping.raw_mapping&.custom_methods &&
                                 xml_mapping.raw_mapping.custom_methods[:to]

            if has_custom_map_all
              # Use legacy path for custom methods
              collector = NamespaceCollector.new(register)
              needs = collector.collect(@root, xml_mapping)

              planner = DeclarationPlanner.new(register)
              plan = planner.plan(@root, xml_mapping, needs, options: options)

              build_element_with_plan(builder, @root, plan, options)
            else
              # Transform model to XmlElement tree first
              transformation = mapper_class.transformation_for(:xml, register)
              xml_element = transformation.transform(@root, options)

              # Phase 1: Collect namespace needs from XmlElement
              collector = NamespaceCollector.new(register)
              needs = collector.collect(xml_element, xml_mapping, mapper_class: mapper_class)

              # Phase 2: Plan declarations with XmlElement tree
              planner = DeclarationPlanner.new(register)
              plan = planner.plan(xml_element, xml_mapping, needs, options: options)

              # Phase 3: Build with plan (still uses model instance for build_element_with_plan)
              build_element_with_plan(builder, @root, plan, options)
            end
          end

          xml_data = builder.xml.to_s
          stripped_data = xml_data.lines.drop(1).join

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

          result += stripped_data
          result
        end

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
                register: register
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
          prefix_info = ElementPrefixResolver.resolve(mapping: xml_mapping, plan: plan)
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
                                                parent_ns_decl: prefix_info[:ns_decl]
                                              ))
            else
              build_unordered_children_with_plan(el, element, plan,
                                                 options.merge(
                                                   mapper_class: mapper_class,
                                                   parent_ns_decl: prefix_info[:ns_decl]
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
        def build_xml_element(xml, element, parent_uses_default_ns: false, parent_element_form_default: nil, parent_namespace_class: nil, plan: nil, xml_mapping: nil)
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
                               element_prefix  # Use child's prefix
                             else
                               nil
                             end

          # FIX: Read prefix from plan if available, otherwise use fallback logic
          prefix = if child_needs_prefix
                    # Priority 2.5 takes precedence
                    child_needs_prefix
                  elsif plan && element_ns_class
                    # Read format decision from DeclarationPlan
                    ns_info = ElementPrefixResolver.resolve(
                      mapping: xml_mapping,
                      plan: plan
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
          else
            # W3C Compliance: Element has no namespace (blank namespace)
            # Check if DeclarationPlan says this element needs xmlns=""
            # The planner already determined this based on W3C semantics during planning phase
            if plan && DeclarationPlanQuery.element_needs_xmlns_blank?(plan, element)
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
          end

          # Check if element was created from nil value with render_nil option
          # Add xsi:nil="true" attribute for W3C compliance
          if element.instance_variable_defined?(:@is_nil) && element.instance_variable_get(:@is_nil)
            attributes["xsi:nil"] = true
          end

          # Create element
          xml.create_and_add_element(tag_name, attributes: attributes, prefix: prefix) do |inner_xml|
            # Handle raw content (map_all directive)
            # If @raw_content exists, add as raw XML
            has_raw_content = false
            if element.instance_variable_defined?(:@raw_content)
              raw_content = element.instance_variable_get(:@raw_content)
              if raw_content && !raw_content.to_s.empty?
                # For Ox, use raw() method to add unescaped content
                inner_xml.xml.raw(raw_content.to_s)
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
                if child.is_a?(Lutaml::Model::XmlDataModel::XmlElement)
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

        # Collect all namespace classes used in the XmlElement tree
        #
        # @param element [XmlDataModel::XmlElement] the root element
        # @return [Set] set of namespace classes used in tree
        def collect_namespaces_from_tree(element)
          namespaces = Set.new

          # Add this element's namespace
          namespaces.add(element.namespace_class) if element.namespace_class

          # Add attribute namespaces
          element.attributes.each do |attr|
            namespaces.add(attr.namespace_class) if attr.namespace_class
          end

          # Recursively collect from children
          element.children.each do |child|
            if child.is_a?(Lutaml::Model::XmlDataModel::XmlElement)
              namespaces.merge(collect_namespaces_from_tree(child))
            end
          end

          namespaces
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

            attribute_def = attribute_definition_for(element, element_rule,
                                                     mapper_class: mapper_class)
            next unless attribute_def

            value = attribute_value_for(element, element_rule)
            next unless element_rule.render?(value, element)

            # Check if value is a Collection instance
            is_collection_instance = value.is_a?(Lutaml::Model::Collection)

            if value && (attribute_def.type(register)&.<=(Lutaml::Model::Serialize) || is_collection_instance)
              handle_nested_elements_with_plan(
                xml,
                value,
                element_rule,
                attribute_def,
                nil,
                options,
                parent_plan: plan,
              )
            else
              # Handle non-model values (strings, etc.)
              add_simple_value(xml, element_rule, value, attribute_def,
                               plan: plan, mapping: xml_mapping, options: options)
            end
          end

          # Process content mapping
          process_content_mapping(element, xml_mapping.content_mapping,
                                  xml, mapper_class)
        end

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
                                                    type: object.type)
            next if element_rule.nil? || options[:except]&.include?(element_rule.to)

            # Handle custom methods
            if element_rule.custom_methods[:to]
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
              attribute_def = attribute_definition_for(element, element_rule,
                                                       mapper_class: mapper_class)
              value = attribute_value_for(element, element_rule)
            end

            next if element_rule == xml_mapping.content_mapping && element_rule.cdata && object.text?

            if element_rule == xml_mapping.content_mapping
              text = element.send(xml_mapping.content_mapping.to)
              text = text[curr_index] if text.is_a?(Array)

              if element.mixed?
                xml.xml.text(text) unless text.nil? || text.empty?
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

              is_collection_instance = current_value.is_a?(Lutaml::Model::Collection)

              if current_value && (attribute_def&.type(register)&.<=(Lutaml::Model::Serialize) || is_collection_instance)
                handle_nested_elements_with_plan(
                  xml,
                  current_value,
                  element_rule,
                  attribute_def,
                  options,
                  parent_plan: plan,
                )
              else
                # Apply transformations if attribute_def exists
                if attribute_def
                  current_value = ExportTransformer.call(current_value,
                                                         element_rule, attribute_def, format: :xml)
                end

                # For mixed content, create elements directly via Ox API to preserve order
                # BUT not for raw attributes which need special handling
                if element.mixed? && !attribute_def&.raw?
                  # Create element directly on the Ox object
                  xml.xml.element(element_rule.name) do |child_element|
                    child_element.text(current_value.to_s) unless Utils.empty?(current_value)
                  end
                else
                  add_simple_value(xml, element_rule, current_value,
                                   attribute_def, plan: plan, mapping: xml_mapping, options: options)
                end
              end
            end
          end

          unless content.empty?
            xml.add_text(xml, content.join)
          end
        end

        # Handle nested model elements with plan
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
                  transformation = item_mapper_class.transformation_for(:xml, register)
                  xml_element = transformation.transform(val, options)

                  # Collect namespace needs from XmlElement tree
                  collector = NamespaceCollector.new(register)
                  item_needs = collector.collect(xml_element, item_mapping, mapper_class: item_mapper_class)

                  # Plan with XmlElement tree (not model instance)
                  planner = DeclarationPlanner.new(register)
                  item_plan = planner.plan(xml_element, item_mapping, item_needs, parent_plan: parent_plan, options: options)
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
                transformation = item_mapper_class.transformation_for(:xml, register)
                xml_element = transformation.transform(val, options)

                # Collect namespace needs from XmlElement tree
                collector = NamespaceCollector.new(register)
                item_needs = collector.collect(xml_element, item_mapping, mapper_class: item_mapper_class)

                # Plan with XmlElement tree (not model instance)
                planner = DeclarationPlanner.new(register)
                item_plan = planner.plan(xml_element, item_mapping, item_needs, parent_plan: parent_plan, options: options)
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
            if plan
              build_element_with_plan(xml, value, plan, element_options)
            else
              # Fallback for cases without plan
              build_element(xml, value, element_options)
            end
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
              DeclarationPlanQuery.declared_at_root_default_format?(plan, mapping.namespace_class)
            else
              false
            end
          end

          # Resolve namespace using the resolver
          ns_result = resolver.resolve_for_element(rule, attribute, mapping, plan, options)
          resolved_prefix = ns_result[:prefix]
          type_ns_info = ns_result[:ns_info]

          # CRITICAL FIX: Type namespace format inheritance for namespace_scope
          # When a type has xml_namespace and that namespace is in the stored plan,
          # inherit the format from the stored plan (preserves input format)
          type_ns_class = if attribute && !rule.namespace_set?
                            type_class = attribute.type(register)
                            type_class.xml_namespace if type_class&.respond_to?(:xml_namespace)
                          end

          format_from_stored_plan = false
          blank_xmlns = false  # Will be set below if needed

          if type_ns_class
            # Check BOTH the current plan (programmatic) and stored plan (round-trip)
            check_plan = plan || options[:__stored_plan]
            if check_plan
              stored_ns_decl = check_plan.namespaces.values.find { |decl| decl.uri == type_ns_class.uri }
              if stored_ns_decl
                # Namespace in plan - inherit its format
                # CRITICAL: local_on_use namespaces MUST use prefix format
                # (can't use default format - parent already using default)
                if stored_ns_decl.local_on_use? || stored_ns_decl.prefix_format?
                  resolved_prefix = stored_ns_decl.prefix
                else
                  resolved_prefix = nil  # Use default format
                end
                format_from_stored_plan = true  # Don't let subsequent logic override this
                blank_xmlns = false  # Using plan namespace format, no xmlns="" needed
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
            # 2. Attribute type doesn't have xml_namespace (native type like :string)
            element_has_no_explicit_ns = !rule.namespace_set?
            type_class = attribute&.type(register)
            type_has_no_ns = !type_class&.respond_to?(:xml_namespace) ||
                             !type_class&.xml_namespace

            # If native type with no explicit namespace, DON'T inherit parent's prefix
            if element_has_no_explicit_ns && type_has_no_ns
              # Native type - force blank namespace (no prefix)
              resolved_prefix = nil
              # Check if parent uses default format - if so, need xmlns="" to opt out
              blank_xmlns = parent_ns_decl && parent_ns_decl.default_format?
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
              blank_xmlns = false
            else
              # Different namespace or no parent context - use standard resolution
              resolved_prefix = ns_result[:prefix]
              blank_xmlns = ns_result[:blank_xmlns]
            end
          end

          # Prepare attributes for element creation
          attributes = {}

          # W3C COMPLIANCE: Use resolver to determine xmlns="" requirement
          if resolver.xmlns_blank_required?(ns_result, parent_uses_default_ns)
            attributes["xmlns"] = ""
          end

          # Check if this namespace needs local declaration (out of scope)
          if resolved_prefix && plan && plan.namespaces
            ns_entry = plan.namespaces.values.find do |ns_decl|
              ns_decl.ns_object.prefix_default == resolved_prefix ||
                (type_ns_info && type_ns_info[:uri] && ns_decl.ns_object.uri == type_ns_info[:uri])
            end

            if ns_entry && ns_entry.local_on_use?
              xmlns_attr = resolved_prefix ? "xmlns:#{resolved_prefix}" : "xmlns"
              attributes[xmlns_attr] = ns_entry.ns_object.uri
            end
          end

          if value.nil?
            xml.create_and_add_element(rule.name,
                                       attributes: attributes.merge({ "xsi:nil" => true }),
                                       prefix: resolved_prefix)
          elsif Utils.empty?(value)
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

        private

        # Helper method to recursively add Ox element to parent
        #
        # @param parent [Ox::Element] Parent Ox element
        # @param ox_element [Ox::Element] Child Ox element to add
        def add_ox_element_to_parent(parent, ox_element)
          # Create new Ox element on parent
          parent.element(ox_element.name) do |child|
            # Add attributes
            ox_element.attributes.each do |attr_name, attr_value|
              child[attr_name] = attr_value
            end

            # Add children recursively
            if ox_element.respond_to?(:nodes)
              ox_element.nodes.each do |node|
                if node.is_a?(::Ox::Element)
                  add_ox_element_to_parent(child, node)
                elsif node.respond_to?(:value)
                  # Text node
                  child.text(node.value)
                end
              end
            end
          end
        end
      end
    end
  end
end
