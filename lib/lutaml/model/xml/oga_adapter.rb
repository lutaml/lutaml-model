require "oga"
require "moxml/adapter/oga"
require_relative "document"
require_relative "oga/document"
require_relative "oga/element"
require_relative "builder/oga"
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

module Lutaml
  module Model
    module Xml
      class OgaAdapter < Document
        include DeclarationHandler
        include PolymorphicValueHandler
        extend DocTypeExtractor

        TEXT_CLASSES = [Moxml::Text, Moxml::Cdata].freeze

        def self.parse(xml, options = {})
          parsed = Moxml::Adapter::Oga.parse(xml)
          root_element = parsed.children.find { |child| child.is_a?(Moxml::Element) }

          # Extract DOCTYPE information
          # Moxml/Oga doesn't directly expose DOCTYPE, extract from raw XML
          doctype_info = extract_doctype_from_xml(xml)

          # Extract input namespace declarations for Issue #3: Namespace Preservation
          input_namespaces = InputNamespaceExtractor.extract(root_element, :oga)

          @root = Oga::Element.new(root_element)
          new(@root, encoding(xml, options), doctype: doctype_info,
              input_namespaces: input_namespaces)
        end

        def to_xml(options = {})
          builder_options = {}
          builder_options[:encoding] = if options.key?(:encoding)
                                         options[:encoding]
                                       elsif options.key?(:parse_encoding)
                                         options[:parse_encoding]
                                       else
                                         "UTF-8"
                                       end

          builder = Builder::Oga.build(builder_options) do |xml|
            if @root.is_a?(Oga::Element)
              @root.build_xml(xml)
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
                                   plan: plan, mapping: xml_mapping)
                end
              end
            end
            return xml
          end

          # Use xmlns declarations from plan
          attributes = {}

          # Apply namespace declarations from plan using extracted module
          attributes.merge!(NamespaceDeclarationBuilder.build_xmlns_attributes(plan))

          # Add regular attributes (non-xmlns)

          xml_mapping.attributes.each do |attribute_rule|
            next if attribute_rule.custom_methods[:to] ||
              options[:except]&.include?(attribute_rule.to)

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
          if element.respond_to?(:schema_location) &&
              element.schema_location.is_a?(Lutaml::Model::SchemaLocation) &&
              !options[:except]&.include?(:schema_location)
            attributes.merge!(element.schema_location.to_xml_attributes)
          end

          # Determine prefix from plan using extracted module
          prefix_info = ElementPrefixResolver.resolve(mapping: xml_mapping, plan: plan)
          prefix = prefix_info[:prefix]

          tag_name = options[:tag_name] || xml_mapping.root_element
          return if options[:except]&.include?(tag_name)

          xml.create_and_add_element(tag_name, prefix: prefix,
                                               attributes: attributes.compact) do
            if ordered?(element, options.merge(mapper_class: mapper_class))
              build_ordered_element_with_plan(xml, element, plan,
                                              options.merge(
                                                mapper_class: mapper_class,
                                                parent_namespace_class: xml_mapping.namespace_class,
                                                parent_ns_decl: prefix_info[:ns_decl]
                                              ))
            else
              build_unordered_children_with_plan(xml, element, plan,
                                                 options.merge(
                                                   mapper_class: mapper_class,
                                                   parent_namespace_class: xml_mapping.namespace_class,
                                                   parent_ns_decl: prefix_info[:ns_decl]
                                                 ))
            end
          end
        end

        # Build element using prepared namespace declaration plan
        # @param xml [Builder] the XML builder
        # @param element [Object] the model instance
        # @param plan [Hash] the declaration plan from DeclarationPlanner
        # @param options [Hash] serialization options
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
            child_plan = plan.child_plan(element_rule.to)

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
                parent_plan: plan,
              )
            elsif element_rule.delegate && attribute_def.nil?
              # Handle non-model values (strings, etc.)
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

        # Build element using prepared namespace declaration plan
        # @param xml [Builder] the XML builder
        # @param element [Object] the model instance
        # @param plan [Hash] the declaration plan from DeclarationPlanner
        # @param options [Hash] serialization options
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
              # BUT without interfering with existing behavior here.

              # Re-reading Document#build_ordered_element:
              # It calls add_to_xml. add_to_xml handles custom_methods.
              # So yes, it calls custom method.

              mapper_class.new.send(element_rule.custom_methods[:to], element,
                                    xml.parent, xml)
              next
            end

            attribute_def = mapper_class.attributes[element_rule.to]
            value = if element.respond_to?(element_rule.to)
                      element.send(element_rule.to)
                    end

            if element_rule == xml_mapping.content_mapping
              next if element_rule.cdata && object.text?

              text = xml_mapping.content_mapping.serialize(element)
              text = text[curr_index] if text.is_a?(Array)

              if element.mixed?
                xml.add_text(xml, text, cdata: element_rule.cdata)
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
              child_plan = plan.child_plan(element_rule.to)

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
                add_simple_value(xml, element_rule, current_value, attribute_def,
                                 plan: plan, mapping: xml_mapping, options: options)
              end
            end
          end

          unless content.empty?
            xml.text content.join
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

                # CRITICAL: Collect and plan for each item individually
                item_mapping = item_mapper_class.mappings_for(:xml)
                if item_mapping
                  collector = NamespaceCollector.new(register)
                  item_needs = collector.collect(val, item_mapping)

                  planner = DeclarationPlanner.new(register)
                  item_plan = planner.plan(val, item_mapping, item_needs, parent_plan: parent_plan, options: options)
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

              # CRITICAL: Collect and plan for each array item individually
              item_mapping = item_mapper_class.mappings_for(:xml)
              if item_mapping
                collector = NamespaceCollector.new(register)
                item_needs = collector.collect(val, item_mapping)

                planner = DeclarationPlanner.new(register)
                item_plan = planner.plan(val, item_mapping, item_needs, parent_plan: parent_plan, options: options)
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
          # Handle array values by creating multiple elements
          if value.is_a?(Array)
            value.each do |val|
              add_simple_value(xml, rule, val, attribute, plan: plan,
                                                      mapping: mapping, options: options)
            end
            return
          end

          # Determine prefix for this element based on namespace rules
          # Initialize namespace resolver
          resolver = NamespaceResolver.new(register)

          # Extract parent_uses_default_ns from options or calculate it
          parent_uses_default_ns = options[:parent_uses_default_ns]
          if parent_uses_default_ns.nil?
            parent_uses_default_ns = if mapping&.namespace_class && plan
              key = mapping.namespace_class.to_key
              ns_decl = plan.namespace(key)
              ns_decl&.declared_here? && ns_decl&.default_format?
            else
              false
            end
          end

          # Resolve namespace using the resolver
          ns_result = resolver.resolve_for_element(rule, attribute, mapping, plan, options)
          resolved_prefix = ns_result[:prefix]
          type_ns_info = ns_result[:ns_info]

          # BUG FIX #49: Check if child element is in same namespace as parent
          # If yes, inherit parent's format (default vs prefix)

          # Get parent's namespace URI
          parent_ns_class = options[:parent_namespace_class]
          parent_ns_decl = options[:parent_ns_decl]
          parent_ns_uri = parent_ns_class&.uri

          # Get child's resolved namespace URI
          child_ns_uri = ns_result[:uri]

          # Only inherit format if child is in SAME namespace as parent (matching URIs)
          if parent_ns_class && parent_ns_decl &&
             child_ns_uri && parent_ns_uri &&
             child_ns_uri == parent_ns_uri
            # Same namespace URI - inherit parent's format
            if parent_ns_decl.prefix_format?
              resolved_prefix = parent_ns_decl.prefix
            else
              # Parent uses default format, child should too (no prefix)
              resolved_prefix = nil
            end
          end

          # Prepare attributes with xmlns if needed
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

        def self.name_of(element)
          return nil if element.nil?

          case element
          when Moxml::Text
            "text"
          when Moxml::Cdata
            "cdata"
          when Moxml::ProcessingInstruction
            "processing_instruction"
          else
            element.name
          end
        end

        def self.prefixed_name_of(node)
          return name_of(node) if TEXT_CLASSES.include?(node.class)

          [node&.namespace&.prefix, node.name].compact.join(":")
        end

        def self.text_of(element)
          element.text
        end

        def self.namespaced_attr_name(attribute)
          attr_ns = attribute.namespace
          attr_name = attribute.name
          return attr_name unless attr_ns

          prefix = attr_name == "lang" ? attr_ns.prefix : attr_ns.uri
          [prefix, attr_name].compact.join(":")
        end

        def self.namespaced_name_of(node)
          return name_of(node) unless node.respond_to?(:namespace)

          [node&.namespace&.uri, node.name].compact.join(":")
        end

        def order
          children.map do |child|
            type = child.text? ? "Text" : "Element"
            Element.new(type, child.unprefixed_name)
          end
        end

        def self.order_of(element)
          element.child.all do |node|
            [Element.new("ProcessingInstruction", node.name)] if node.is_a?(Moxml::ProcessingInstruction)
          end
            .flatten
          super
        end
      end
    end
  end
end
