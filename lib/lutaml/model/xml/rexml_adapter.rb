require "rexml/document"
require "moxml"
require "moxml/adapter/rexml"
require_relative "document"
require_relative "rexml/element"
require_relative "builder/rexml"
require_relative "namespace_collector"
require_relative "declaration_planner"

module Lutaml
  module Model
    module Xml
      class RexmlAdapter < Document
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

          @root = Rexml::Element.new(root_element, target_encoding: parse_encoding)
          new(@root, parse_encoding)
        end

        def to_xml(options = {})
          builder_options = { encoding: determine_encoding(options) }

          builder = Builder::Rexml.build(builder_options) do |xml|
            if @root.is_a?(Rexml::Element)
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
            "#cdata-section"
          else
            element.name
          end
        end

        def self.prefixed_name_of(node)
          return name_of(node) if TEXT_CLASSES.include?(node.class)

          [node&.namespace&.prefix, node.name].compact.join(":")
        end

        def self.text_of(element)
          element.content
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

          escaped_xml = xml.gsub(/&(?![a-zA-Z]+;|#[0-9]+;|#x[0-9a-fA-F]+;)/, "&amp;")
          Moxml::Adapter::Rexml.parse(escaped_xml).root
        end

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
            # doesn't exist directly on the main class
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
            xml.add_text(xml, content.join)
          end
        end

        def handle_nested_elements_with_plan(xml, value, rule, attribute, plan, options)
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

        def add_simple_value(xml, rule, value, attribute, plan: nil, mapping: nil)
          # Handle array values by creating multiple elements
          if value.is_a?(Array)
            value.each do |val|
              add_simple_value(xml, rule, val, attribute, plan: plan, mapping: mapping)
            end
            return
          end

          # Determine prefix for this element based on namespace rules
          resolved_prefix = nil

          # Check for explicit namespace on the rule
          if rule.namespace_set?
            resolved_prefix = rule.prefix
          end

          if value.nil?
            xml.create_and_add_element(rule.name,
                                       attributes: { "xsi:nil" => true },
                                       prefix: resolved_prefix)
          elsif Utils.empty?(value)
            xml.create_and_add_element(rule.name,
                                       prefix: resolved_prefix)
          elsif rule.raw_mapping?
            xml.add_xml_fragment(xml, value)
          else
            xml.create_and_add_element(rule.name,
                                       prefix: resolved_prefix) do
              add_value(xml, value, attribute, cdata: rule.cdata)
            end
          end
        end

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

          prefixed_xml.create_and_add_element(tag_name, attributes: attributes) do |el|
            process_element_order(el, element, xml_mapping, mapper_class, options)
          end
        end

        def process_element_order(builder, element, xml_mapping, mapper_class, options)
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
          element_rule = xml_mapping.find_by_name(object.name, type: object.type)

          return if skip_element_rule?(element_rule, options)

          attribute_def = attribute_definition_for(element, element_rule, mapper_class: mapper_class)
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
            handle_ordered_content_text(builder, element, element_rule, xml_mapping, curr_index, content)
          elsif !value.nil? || element_rule.render_nil?
            add_ordered_element_value(builder, element, attribute_def, value, curr_index,
                                      element_rule, options, mapper_class)
          end
        end

        def handle_ordered_content_text(builder, element, element_rule, xml_mapping, curr_index, content)
          text = xml_mapping.content_mapping.serialize(element)
          text = text[curr_index] if text.is_a?(Array)

          return builder.add_text(builder, text, cdata: element_rule.cdata) if element.mixed?

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
