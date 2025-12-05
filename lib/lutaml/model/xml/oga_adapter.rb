require "oga"
require "moxml/adapter/oga"
require_relative "document"
require_relative "oga/document"
require_relative "oga/element"
require_relative "builder/oga"
require_relative "namespace_collector"
require_relative "declaration_planner"

module Lutaml
  module Model
    module Xml
      class OgaAdapter < Document
        TEXT_CLASSES = [Moxml::Text, Moxml::Cdata].freeze

        def self.parse(xml, options = {})
          parsed = Moxml::Adapter::Oga.parse(xml)
          root_element = parsed.children.find { |child| child.is_a?(Moxml::Element) }
          @root = Oga::Element.new(root_element)
          new(@root, encoding(xml, options))
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
          options[:declaration] ? declaration(options) + xml_data : xml_data
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
          plan ||= {
            namespaces: {},
            children_plans: {},
            type_namespaces: {},
          }

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
              prefix = xml_mapping.namespace_class.prefix_default
            end
          end

          tag_name = options[:tag_name] || xml_mapping.root_element
          return if options[:except]&.include?(tag_name)

          xml.create_and_add_element(tag_name, prefix: prefix,
                                               attributes: attributes.compact) do
            if ordered?(element, options.merge(mapper_class: mapper_class))
              build_ordered_element_with_plan(xml, element, plan,
                                              options.merge(mapper_class: mapper_class))
            else
              build_unordered_children_with_plan(xml, element, plan,
                                                 options.merge(mapper_class: mapper_class))
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
            elsif element_rule.delegate && attribute_def.nil?
              # Handle non-model values (strings, etc.)
              add_simple_value(xml, element_rule, value, nil, plan: plan,
                                                              mapping: xml_mapping)
            else
              add_simple_value(xml, element_rule, value, attribute_def,
                               plan: plan, mapping: xml_mapping)
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
              build_element_with_plan(xml, val, plan, element_options)
            end
          else
            build_element_with_plan(xml, value, plan, element_options)
          end
        end

        # Add simple (non-model) values to XML
        def add_simple_value(xml, rule, value, attribute, plan: nil,
mapping: nil)
          # Handle array values by creating multiple elements
          if value.is_a?(Array)
            value.each do |val|
              add_simple_value(xml, rule, val, attribute, plan: plan,
                                                          mapping: mapping)
            end
            return
          end

          # Determine prefix for this element based on namespace rules
          resolved_prefix = nil
          false
          nil

          # TYPE NAMESPACE INTEGRATION: Check attribute's type namespace first
          # Priority: explicit mapping namespace > Type namespace > parent inheritance
          type_ns_info = nil

          # Check for explicit namespace on the rule
          if rule.namespace_set?
            resolved_prefix = rule.prefix
            if rule.namespace
              # Only declare if not already in plan
              already_declared = plan && plan[:namespaces]&.any? do |_key, ns_config|
                ns_config[:ns_object].uri == rule.namespace && ns_config[:declared_at] == :here
              end
              !already_declared
              rule.namespace
            end
          elsif plan && plan[:type_namespaces] && plan[:type_namespaces][rule.to]
            # Type namespace - this attribute's type defines its own namespace
            # Priority: Type namespace takes precedence over parent inheritance
            type_ns_class = plan[:type_namespaces][rule.to]
            key = type_ns_class.to_key
            ns_config = plan[:namespaces][key]
            if ns_config && ns_config[:format] == :prefix
              resolved_prefix = type_ns_class.prefix_default
            end
          end

          # If no explicit namespace and no Type namespace, check attribute's type namespace next
          if !resolved_prefix && !rule.namespace_set?

            # Only check type namespace if attribute is present
            type_ns_info = rule.resolve_namespace(
              attr: attribute,
              register: register,
              parent_ns_uri: mapping&.namespace_uri,
              parent_ns_class: mapping&.namespace_class,
            )

            # Check if type namespace provides prefix and URI
            if type_ns_info[:prefix]
              resolved_prefix = type_ns_info[:prefix]
            end

            # Check only once for xmlns declaration (if URI present in ns_info)
            if type_ns_info[:uri] && !resolved_prefix
              uri = type_ns_info[:uri]

              already_declared = plan && plan[:namespaces]&.any? do |_key, ns_config|
                ns_config[:ns_object].uri == uri && ns_config[:declared_at] == :here
              end
              !already_declared
              uri
            end
          end

          # If explicit Type is set (ignores parent namespace settings),
          # then the above rules can be overridden.
          # No need to fallback to parent namespace inheritance directly; let child elements manage that.

          # Inherit from parent only as a fallback if all other checks failed
          if !resolved_prefix

            # Check parent namespaces (mapped or defaulted), but only if the attribute
            # allows being declared on this level
            # (Some types may be declared only on root or higher levels)
            if mapping&.namespace_uri
              # NAMESPACE PREFIX INHERITANCE: Comprehensive case handling
              # Cases:
              # 1. namespace: :inherit → always use parent's prefix
              # 2. Element namespace matches parent → check plan[:namespaces]
              # 3. Element is unqualified but should inherit → check parent format
              # 4. Element has explicit namespace: nil → NO prefix ever

              if rule.namespace_param == :inherit
                # Case 1: Explicit :inherit - always use parent's prefix
                if mapping.namespace_class
                  key = mapping.namespace_class.to_key
                  ns_config = plan[:namespaces][key]
                  if ns_config && ns_config[:format] == :prefix
                    resolved_prefix = mapping.namespace_class.prefix_default
                  end
                end
              elsif type_ns_info && type_ns_info[:uri] && type_ns_info[:uri] == mapping.namespace_uri
                # Case 2: Element has namespace matching parent - check format
                if plan && mapping.namespace_class
                  key = mapping.namespace_class.to_key
                  ns_config = plan[:namespaces][key]
                  if ns_config && ns_config[:format] == :prefix
                    resolved_prefix = mapping.namespace_class.prefix_default
                  end
                end
              elsif type_ns_info && type_ns_info[:uri] && type_ns_info[:uri] != mapping.namespace_uri
                # Case 2b: Element has DIFFERENT namespace - use its own prefix
                # Find the namespace class by URI
                if plan && plan[:namespaces]
                  ns_entry = plan[:namespaces].find do |_key, ns_config|
                    ns_config[:ns_object].uri == type_ns_info[:uri]
                  end
                  if ns_entry
                    _key, ns_config = ns_entry
                    if ns_config[:format] == :prefix
                      resolved_prefix = ns_config[:ns_object].prefix_default
                    end
                  end
                end
              elsif !rule.namespace_set? && type_ns_info && type_ns_info[:uri] && type_ns_info[:uri] == mapping.namespace_uri
                # Case 3: Element has SAME namespace as parent (not nil, not unqualified)
                # Element has a resolved namespace that matches parent -> inherit parent format
                # Truly unqualified elements (type_ns_info[:uri].nil?) do NOT inherit
                if plan && mapping.namespace_class
                  key = mapping.namespace_class.to_key
                  ns_config = plan[:namespaces][key]
                  if ns_config && ns_config[:format] == :prefix
                    resolved_prefix = mapping.namespace_class.prefix_default
                  end
                end
              end
              # Case 4: explicit namespace: nil falls through with resolved_prefix = nil
              # Case 5: truly unqualified (type_ns_info[:uri].nil?) falls through with resolved_prefix = nil
            end

            # No inheritance from parent namespace if mapping not available
            resolved_prefix ||= nil
          end

          # Parent namespace attribute will be inherited in child elements if
          # needed. Document interpreters must be prepared for this.

          # Prepare attributes with xmlns if needed
          attributes = {}
          # FIX: Never declare Type namespaces locally - rely on root-level declarations from plan
          # This prevents over-declaration and follows "never declare twice" principle
          # Type namespaces should be declared at root level by DeclarationPlanner

          # Check if this namespace needs local declaration (out of scope)
          if resolved_prefix && plan && plan[:namespaces]
            # Find the namespace config for this prefix
            ns_entry = plan[:namespaces].find do |_key, ns_config|
              ns_config[:ns_object].prefix_default == resolved_prefix ||
                (type_ns_info && type_ns_info[:uri] && ns_config[:ns_object].uri == type_ns_info[:uri])
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
