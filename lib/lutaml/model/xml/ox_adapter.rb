require "ox"
require_relative "document"
require_relative "builder/ox"
require_relative "namespace_collector"
require_relative "declaration_planner"

module Lutaml
  module Model
    module Xml
      class OxAdapter < Document
        def self.parse(xml, options = {})
          Ox.default_options = Ox.default_options.merge(encoding: encoding(xml,
                                                                           options))

          parsed = Ox.parse(xml)
          # @root = OxElement.new(parsed)
          # Ox.parse returns Ox::Document if XML has declaration, Ox::Element otherwise
          root_element = parsed.is_a?(::Ox::Document) ? parsed.nodes.first : parsed
          @root = OxElement.new(root_element)
          new(@root, Ox.default_options[:encoding])
        end

        def to_xml(options = {})
          builder_options = { version: options[:version] }

          builder_options[:encoding] = if options.key?(:encoding)
                                         options[:encoding] unless options[:encoding].nil?
                                       elsif options.key?(:parse_encoding)
                                         options[:parse_encoding]
                                       else
                                         "UTF-8"
                                       end

          builder = Builder::Ox.build(builder_options)
          builder.xml.instruct(:xml, encoding: builder_options[:encoding])

          if @root.is_a?(Lutaml::Model::Xml::OxElement)
            @root.build_xml(builder)
          else
            # THREE-PHASE ARCHITECTURE
            mapper_class = options[:mapper_class] || @root.class
            xml_mapping = mapper_class.mappings_for(:xml, register)

            # Phase 1: Collect namespace needs
            collector = NamespaceCollector.new(register)
            needs = collector.collect(@root, xml_mapping)

            # Phase 2: Plan declarations
            planner = DeclarationPlanner.new(register)
            plan = planner.plan(@root, xml_mapping, needs, options: options)

            # Phase 3: Build with plan
            build_element_with_plan(builder, @root, plan, options)
          end

          xml_data = builder.xml.to_s
          stripped_data = xml_data.lines.drop(1).join
          options[:declaration] ? declaration(options) + stripped_data : stripped_data
        end

        # Build element using prepared namespace declaration plan
        #
        # @param xml [Builder] the XML builder
        # @param element [Object] the model instance
        # @param plan [Hash] the declaration plan from DeclarationPlanner
        # @param options [Hash] serialization options
        def build_element_with_plan(xml, element, plan, options = {})
          mapper_class = options[:mapper_class] || element.class
          xml_mapping = mapper_class.mappings_for(:xml, register)
          return xml unless xml_mapping

          # Use xmlns declarations from plan
          attributes = {}
          plan ||= {
            namespaces: {},
            children_plans: {},
            type_namespaces: {},
          }

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
          xml_mapping.attributes(register).each do |attribute_rule|
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
              # Resolve attribute namespace
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
              # CRITICAL: Use the ns_object from plan (may be override with custom prefix)
              prefix = ns_config[:ns_object].prefix_default
            end
          end

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
                                              options.merge(mapper_class: mapper_class))
            else
              build_unordered_children_with_plan(el, element, plan,
                                                 options.merge(mapper_class: mapper_class))
            end
          end
        end

        def build_unordered_children_with_plan(xml, element, plan, options)
          mapper_class = options[:mapper_class] || element.class
          xml_mapping = mapper_class.mappings_for(:xml, register)

          # Process child elements with their plans (INCLUDING raw_mapping for map_all)
          mappings = xml_mapping.elements(register) + [xml_mapping.raw_mapping].compact
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

            # Get child's plan if available
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
              # Handle non-model values (strings, etc.)
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
          xml_mapping = mapper_class.mappings_for(:xml, register)

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
                attribute_def = delegate_obj.class.attributes(register)[element_rule.to]
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

              if current_value && attribute_def&.type(register)&.<=(Lutaml::Model::Serialize)
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

                add_simple_value(xml, element_rule, current_value,
                                 attribute_def, plan: plan, mapping: xml_mapping)
              end
            end
          end

          unless content.empty?
            xml.add_text(xml, content.join)
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
          use_prefix = false
          parent_prefix = nil

          if rule.namespace_param == :inherit
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

          # Use resolved namespace directly
          resolved_prefix = if rule.namespace_param == :inherit
                              parent_prefix
                            elsif use_prefix && parent_prefix
                              parent_prefix
                            else
                              ns_info[:prefix]
                            end

          # Prepare attributes for element creation
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
      end

      class OxElement < XmlElement
        def initialize(node, root_node: nil, default_namespace: nil)
          case node
          when String
            super("text", {}, [], node, parent_document: root_node, name: "text", explicit_no_namespace: false)
          when Ox::Comment
            super("comment", {}, [], node.value, parent_document: root_node, name: "comment", explicit_no_namespace: false)
          when Ox::CData
            super("#cdata-section", {}, [], node.value, parent_document: root_node, name: "#cdata-section", explicit_no_namespace: false)
          else
            # Check for xmlns="" in node's attributes before processing
            has_empty_xmlns = node.attributes[:xmlns] == ""
            has_no_prefix = separate_name_and_prefix(node).first.nil?

            namespace_attributes(node.attributes).each do |(name, value)|
              ns = XmlNamespace.new(value, name)

              if root_node && ns.prefix
                root_node.add_namespace(ns)
              elsif root_node.nil?
                add_namespace(ns)
              end

              # Set default_namespace from xmlns attribute (if not empty)
              default_namespace = ns.uri if ns.prefix.nil? && value != ""
            end

            # Use shared helper to detect explicit no namespace
            explicit_no_namespace = XmlElement.detect_explicit_no_namespace(
              has_empty_xmlns: has_empty_xmlns,
              node_namespace_nil: has_no_prefix, # Ox nodes without prefix have no namespace
            )

            attributes = node.attributes.each_with_object({}) do |(name, value), hash|
              next if attribute_is_namespace?(name)

              namespace_prefix = name.to_s.split(":").first
              if (n = name.to_s.split(":")).length > 1
                namespace = (root_node || self).namespaces[namespace_prefix]&.uri
                namespace ||= XML_NAMESPACE_URI
                prefix = n.first
              end

              hash[name.to_s] = XmlAttribute.new(
                name.to_s,
                value,
                namespace: namespace,
                namespace_prefix: prefix,
              )
            end

            prefix, name = separate_name_and_prefix(node)

            super(
              node,
              attributes,
              parse_children(node, root_node: root_node || self,
                                   default_namespace: default_namespace),
              node.text,
              parent_document: root_node,
              name: name,
              namespace_prefix: prefix,
              default_namespace: default_namespace,
              explicit_no_namespace: explicit_no_namespace
            )
          end
        end

        def separate_name_and_prefix(node)
          name = node.name.to_s

          return [nil, name] unless name.include?(":")
          return [nil, name] if name.start_with?("xmlns:")

          prefix, _, name = name.partition(":")
          [prefix, name]
        end

        def to_xml
          return text if text?

          build_xml.xml.to_s
        end

        def inner_xml
          # Ox builder by default, adds a newline at the end, so `chomp` is used
          children.map { |child| child.to_xml.chomp }.join
        end

        def build_xml(builder = nil)
          builder ||= Builder::Ox.build
          attrs = build_attributes(self)

          if text?
            builder.add_text(builder, text)
          else
            builder.create_and_add_element(name, attributes: attrs) do |el|
              children.each { |child| child.build_xml(el) }
            end
          end

          builder
        end

        def namespace_attributes(attributes)
          attributes.select { |attr| attribute_is_namespace?(attr) }
        end

        def text?
          # false
          children.empty? && text&.length&.positive?
        end

        def build_attributes(node)
          attrs = node.attributes.transform_values(&:value)

          node.own_namespaces.each_value do |namespace|
            attrs[namespace.attr_name] = namespace.uri
          end

          attrs
        end

        def nodes
          children
        end

        def cdata
          super || cdata_children.first&.text
        end

        def text
          super || cdata
        end

        private

        def parse_children(node, root_node: nil, default_namespace: nil)
          node.nodes.map do |child|
            OxElement.new(child, root_node: root_node,
                                 default_namespace: default_namespace)
          end
        end
      end
    end
  end
end
