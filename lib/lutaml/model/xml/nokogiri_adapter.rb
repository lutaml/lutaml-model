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

        def to_xml(options = {})
          # Accept xml_declaration from options if present (for model serialization)
          @xml_declaration = options[:xml_declaration] if options[:xml_declaration]

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
              mapping = mapper_class.mappings_for(:xml)

              # Phase 1: Collect namespace needs
              collector = NamespaceCollector.new(@register)
              needs = collector.collect(@root, mapping)

              # Phase 2: Plan declarations
              # Pass input_namespaces to enable Tier 1 priority system (Issue #3)
              planner = DeclarationPlanner.new(@register)
              plan_options = options.merge(input_namespaces: @input_namespaces)
              plan = planner.plan(@root, mapping, needs, options: plan_options)

              # Phase 3: Build with plan
              build_element_with_plan(xml, @root, plan, options)
            end
          end

          xml_options = {}
          if options[:pretty]
            xml_options[:indent] = 2
          end

          xml_data = builder.doc.root.to_xml(xml_options)

          result = ""

          # Handle XML declaration based on Issue #1: XML Declaration Preservation
          if should_include_declaration?(options)
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
            value = attr.serialize(value, :xml, @register) if attr
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
          if element.respond_to?(:schema_location) &&
              element.schema_location.is_a?(Lutaml::Model::SchemaLocation) &&
              !options[:except]&.include?(:schema_location)
            attributes.merge!(element.schema_location.to_xml_attributes)
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
                                                parent_namespace_class: mapping.namespace_class,
                                                parent_ns_decl: ns_decl
                                              ))
            else
              build_unordered_children_with_plan(xml, element, plan,
                                                 options.merge(
                                                   mapper_class: mapper_class,
                                                   parent_prefix: prefix,
                                                   parent_uses_default_ns: this_element_uses_default_ns,
                                                   parent_element_form_default: parent_element_form_default,
                                                   parent_namespace_class: mapping.namespace_class,
                                                   parent_ns_decl: ns_decl
                                                 ))
            end
          end
        end

        def build_unordered_children_with_plan(xml, element, plan, options)
          mapper_class = options[:mapper_class] || element.class
          mapping = mapper_class.mappings_for(:xml)

          # Process child elements with their plans (INCLUDING raw_mapping for map_all)
          mappings = mapping.elements + [mapping.raw_mapping].compact
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

            if value && (attribute_def&.type(@register)&.<=(Lutaml::Model::Serialize) || is_collection_instance)
              handle_nested_elements_with_plan(
                xml,
                value,
                element_rule,
                attribute_def,
                child_plan,
                options,
                parent_plan: plan,
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
                                                                mapping: mapping, options: options)
              else
                add_simple_value(xml, element_rule, value, attribute_def,
                                 plan: plan, mapping: mapping, options: options)
              end
            end
          end

          # Process content mapping
          process_content_mapping(element, mapping.content_mapping,
                                  xml, mapper_class)
        end

        def build_ordered_element_with_plan(xml, element, plan, options)
          mapper_class = options[:mapper_class] || element.class
          mapping = mapper_class.mappings_for(:xml)

          index_hash = ::Hash.new { |key, value| key[value] = -1 }
          content = []

          element.element_order.each do |object|
            object_key = "#{object.name}-#{object.type}"
            curr_index = index_hash[object_key] += 1

            element_rule = mapping.find_by_name(object.name,
                                                    type: object.type)
            next if element_rule.nil? || options[:except]&.include?(element_rule.to)

            # Handle custom methods
            if element_rule.custom_methods[:to]
              # Call the custom method to handle this attribute
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

            if element_rule == mapping.content_mapping
              next if element_rule.cdata && object.text?

              text = mapping.content_mapping.serialize(element)
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
              child_plan = plan.child_plan(element_rule.to)

              is_collection_instance = current_value.is_a?(Lutaml::Model::Collection)

              if current_value && (attribute_def&.type(@register)&.<=(Lutaml::Model::Serialize) || is_collection_instance)
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

                add_simple_value(xml, element_rule, current_value, attribute_def,
                                 plan: plan, mapping: mapping, options: options)
              end
            end
          end

          unless content.empty?
            xml.text content.join
          end
        end

        # Handle nested model elements with plan
        def handle_nested_elements_with_plan(xml, value, rule, attribute,
child_plan, options, parent_plan: nil, parent_uses_default_ns: nil)
          element_options = options.merge(
            rule: rule,
            attribute: attribute,
            tag_name: rule.name,
            mapper_class: attribute.type(@register), # Override with child's type
          )

          # CRITICAL FIX: For wrappers (like CurveArrayProperty),
          # child_plan is the plan for the wrapper, which contains children_plans for the actual items.
          # When serializing the wrapper, we'll recursively call build_element_with_plan,
          # which will use child_plan[:children_plans] to find plans for the wrapper's children.
          # So we don't need special logic here - just pass child_plan as-is.

          # Extract items from Collection instances
          if value.is_a?(Lutaml::Model::Collection)
            value = value.collection
          end

          case value
          when Array
            # Check if items are simple types (Value) or models (Serialize)

            attr_type = attribute.type(@register)
            if attr_type <= Lutaml::Model::Type::Value
              # Simple types - use add_simple_value for each item
              value.each do |val|
                add_simple_value(xml, rule, val, attribute, plan: parent_plan,
                                mapping: options[:mapper_class]&.mappings_for(:xml), options: options)
              end
            else
              # Model types - build elements with plans
              value.each do |val|
                # For polymorphic arrays, use each item's actual class
                item_mapper_class = if polymorphic_value?(attribute, val)
                                      val.class
                                    else
                                      attribute.type(@register)
                                    end

                # CRITICAL FIX: Collect and plan for each array item individually
                # This ensures each item's actual attributes determine namespace declarations
                item_mapping = item_mapper_class.mappings_for(:xml)
                if item_mapping
                  collector = NamespaceCollector.new(@register)
                  item_needs = collector.collect(val, item_mapping)

                  planner = DeclarationPlanner.new(@register)
                  # Use parent_plan (collection's plan) as parent for items
                  item_plan = planner.plan(val, item_mapping, item_needs, parent_plan: parent_plan, options: options)
                else
                  item_plan = child_plan
                end

                item_options = element_options.merge(mapper_class: item_mapper_class)
                build_element_with_plan(xml, val, item_plan, item_options)
              end
            end
          else
            # For single polymorphic values, use the value's actual class
            if polymorphic_value?(attribute, value)
              element_options = element_options.merge(mapper_class: value.class)
            end
            build_element_with_plan(xml, value, child_plan, element_options)
          end
        end

        # Add simple (non-model) values to XML
        def add_simple_value(xml, rule, value, attribute, plan: nil,
mapping: nil, options: {})
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
                                                          mapping: mapping, options: options)
            end
            return
          end

          # BUG FIX #49: Check if child element is in same namespace as parent
          # If yes, inherit parent's format (default vs prefix)

          # Always resolve namespace first to get the child's actual namespace URI
          resolver = NamespaceResolver.new(@register)
          ns_result = resolver.resolve_for_element(rule, attribute, mapping, plan, options)

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
            # No blank xmlns needed when inheriting
            blank_xmlns = false
          else
            # Different namespace or no parent context - use standard resolution
            resolved_prefix = ns_result[:prefix]
            blank_xmlns = ns_result[:blank_xmlns]
          end

          # Prepare attributes
          attributes = {}

          # Add xmlns="" if needed
          if blank_xmlns
            attributes["xmlns"] = ""
          end

          # Native type inheritance fix: handle local_on_use xmlns="" even when parents uses default format
          xmlns_prefix = nil
          xmlns_ns = nil
          if mapping&.namespace_class && plan
            xmlns_ns = plan.namespace_for_class(mapping.namespace_class)
            xmlns_prefix = xmlns_ns&.prefix
          end
          attributes["xmlns:#{xmlns_prefix}"] = xmlns_ns&.uri || mapping.namespace_uri if xmlns_ns&.local_on_use? && !mapping.namespace_uri

          # Check if this namespace needs local declaration (out of scope)
          if resolved_prefix && plan && ns_result[:uri]
            # Find the namespace config for this prefix/URI
            ns_decl = plan.namespaces.values.find { |decl| decl.uri == ns_result[:uri] }

            # If namespace is marked for local declaration, add xmlns attribute
            if ns_decl&.local_on_use?
              # FIX: Handle both default (nil prefix) and prefixed namespaces
              xmlns_attr = if resolved_prefix
                             "xmlns:#{resolved_prefix}"
                           else
                             "xmlns"
                           end
              attributes[xmlns_attr] = ns_decl.uri
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
          elsif value.is_a?(::Hash) && attribute&.type(@register) == Lutaml::Model::Type::Hash
            # Check if value is Hash type that needs wrapper - do this BEFORE any wrapping/serialization
            # Value is already transformed by ExportTransformer before reaching here
            xml.create_and_add_element(rule.name,
                                       attributes: attributes.empty? ? nil : attributes,
                                       prefix: resolved_prefix) do |params|
              value.each do |key, val|
                xml.create_and_add_element(key.to_s) do |inner_xml|
                  xml.text val.to_s
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
    end
  end
end
