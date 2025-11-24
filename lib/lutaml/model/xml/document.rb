require_relative "../mapping_hash"
require_relative "xml_element"
require_relative "xml_attribute"
require_relative "xml_namespace"
require_relative "element"

module Lutaml
  module Model
    module Xml
      class Document
        attr_reader :root, :encoding, :register

        def initialize(root, encoding = nil, register: nil, **options)
          @root = root
          @encoding = encoding
          @register = setup_register(register)
          @options = options  # NEW: Store options
        end

        def self.parse(xml, _options = {})
          raise NotImplementedError, "Subclasses must implement `parse`."
        end

        def children
          @root.children
        end

        def attributes
          root.attributes
        end

        def self.encoding(xml, options)
          if options.key?(:encoding)
            options[:encoding]
          else
            xml.encoding.to_s
          end
        end

        def declaration(options)
          version = "1.0"
          version = options[:declaration] if options[:declaration].is_a?(String)

          encoding = options[:encoding] ? "UTF-8" : nil
          encoding = options[:encoding] if options[:encoding].is_a?(String)

          declaration = "<?xml version=\"#{version}\""
          declaration += " encoding=\"#{encoding}\"" if encoding
          declaration += "?>\n"
          declaration
        end

        def to_h
          parse_element(@root)
        end

        def order
          @root.order
        end

        def handle_nested_elements(builder, value, options = {})
          element_options = build_options_for_nested_elements(options)

          case value
          when Array
            value.each { |val| build_element(builder, val, element_options) }
          else
            build_element(builder, value, element_options)
          end
        end

        def build_options_for_nested_elements(options = {})
          attribute = options.delete(:attribute)
          rule = options.delete(:rule)

          return {} unless rule

          # Preserve critical options before they're lost
          use_prefix_val = options[:use_prefix]
          declared_namespaces_val = options[:declared_namespaces]
          parent_namespace_scope_attrs_val = options[:parent_namespace_scope_attrs]

          options[:namespace_prefix] = rule.prefix if rule&.namespace_set?
          options[:mixed_content] = rule.mixed_content
          options[:tag_name] = rule.name

          options[:mapper_class] = attribute&.type(register) if attribute
          options[:set_namespace] = set_namespace?(rule)

          # Propagate xml_attributes (namespace declarations) to nested elements
          # This allows nested models to inherit parent's namespace_scope declarations
          options[:xml_attributes] = options[:xml_attributes] if options.key?(:xml_attributes)

          # Restore preserved options
          options[:use_prefix] = use_prefix_val if use_prefix_val
          options[:declared_namespaces] = declared_namespaces_val if declared_namespaces_val
          options[:parent_namespace_scope_attrs] = parent_namespace_scope_attrs_val if parent_namespace_scope_attrs_val

          options
        end

        def parse_element(element, klass = nil, format = nil)
          result = Lutaml::Model::MappingHash.new
          result.node = element
          result.item_order = self.class.order_of(element)

          element.children.each do |child|
            if klass&.<= Serialize
              attr = klass.attribute_for_child(self.class.name_of(child),
                                               format)
            end

            if child.respond_to?(:text?) && child.text?
              result.assign_or_append_value(
                self.class.name_of(child),
                self.class.text_of(child),
              )
              next
            end

            result["elements"] ||= Lutaml::Model::MappingHash.new
            result["elements"].assign_or_append_value(
              self.class.namespaced_name_of(child),
              parse_element(child, attr&.type(register) || klass, format),
            )
          end

          if element.attributes&.any?
            result["attributes"] =
              attributes_hash(element)
          end

          result.merge(attributes_hash(element))
          result
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

        def build_element(xml, element, options = {})
          if ordered?(element, options)
            build_ordered_element(xml, element, options)
          else
            build_unordered_element(xml, element, options)
          end
        end

        def add_to_xml(xml, element, prefix, value, options = {})
          attribute = options[:attribute]
          rule = options[:rule]

          if rule.custom_methods[:to]
            options[:mapper_class].new.send(rule.custom_methods[:to], element,
                                            xml.parent, xml)
            return
          end

          if rule.can_transform_to?(
            attribute, :xml
          )
            return add_transformed_value(xml, rule,
                                         rule.transform_value(attribute, value, :to, :xml))
          end

          # Only transform when recursion is not called
          if attribute && (!attribute.collection? || attribute.collection_instance?(value))
            value = ExportTransformer.call(value, rule, attribute)
          end

          if attribute && attribute.collection_instance?(value) && !Utils.empty_collection?(value)
            value.each do |item|
              add_to_xml(xml, element, prefix, item, options)
            end

            return
          end

          return if !render_element?(rule, element, value)

          value = rule.render_value_for(value)

          # Resolve namespace for this element
          ns_info = resolve_element_namespace(rule, attribute, options)
          resolved_prefix = ns_info[:prefix] || prefix

          if value && attribute && (attribute.type(register)&.<= Lutaml::Model::Serialize)
            handle_nested_elements(
              xml,
              value,
              options.merge({ rule: rule, attribute: attribute }),
            )
          elsif value.nil?
            xml.create_and_add_element(rule.name,
                                       attributes: { "xsi:nil" => true },
                                       prefix: resolved_prefix)
          elsif Utils.empty?(value)
            xml.create_and_add_element(rule.name, prefix: resolved_prefix)
          elsif rule.raw_mapping?
            xml.add_xml_fragment(xml, value)
          elsif rule.prefix_set? || resolved_prefix
            xml.create_and_add_element(rule.name, prefix: resolved_prefix) do
              add_value(xml, value, attribute, cdata: rule.cdata)
            end
          else
            xml.create_and_add_element(rule.name) do
              add_value(xml, value, attribute, cdata: rule.cdata)
            end
          end
        end

        def add_transformed_value(xml, rule, value)
          if value.is_a?(Array)
            value.each do |val|
              add_transformed_value(xml, rule, val)
            end
          end

          xml.create_and_add_element(rule.name) do
            xml.add_text(xml, value, cdata: rule.cdata)
          end
        end

        def add_value(xml, value, attribute, cdata: false)
          if !value.nil?
            serialized_value = attribute.serialize(value, :xml, register)
            if attribute.raw?
              xml.add_xml_fragment(xml, value)
            elsif attribute.type(register) == Lutaml::Model::Type::Hash
              serialized_value.each do |key, val|
                xml.create_and_add_element(key) do |element|
                  element.text(val)
                end
              end
            else
              xml.add_text(xml, serialized_value, cdata: cdata)
            end
          end
        end

        def build_unordered_element(xml, element, options = {})
          mapper_class = determine_mapper_class(element, options)
          xml_mapping = mapper_class.mappings_for(:xml)
          return xml unless xml_mapping

          options[:parent_namespace] ||= nil

          # Initialize namespace registry to track declared xmlns through build chain
          options[:declared_namespaces] ||= {}

          # Inherit parent's namespace_scope declarations if available
          if options[:parent_namespace_scope_attrs]
            options[:xml_attributes] ||= {}
            options[:xml_attributes].merge!(options[:parent_namespace_scope_attrs])
          end

          attributes = build_element_attributes(element, xml_mapping, options)
          prefix = determine_namespace_prefix(options, xml_mapping)

          # Register namespaces declared in this element's attributes
          if attributes
            attributes.each do |k, v|
              if k.start_with?("xmlns:")
                prefix_name = k.sub("xmlns:", "")
                options[:declared_namespaces][prefix_name] = v
              elsif k == "xmlns"
                options[:declared_namespaces][:default] = v
              end
            end
          end

          prefixed_xml = xml.add_namespace_prefix(prefix)
          tag_name = options[:tag_name] || xml_mapping.root_element

          return if options[:except]&.include?(tag_name)

          prefixed_xml.create_and_add_element(tag_name, prefix: prefix,
                                                        attributes: attributes) do
            if options.key?(:namespace_prefix) && !options[:namespace_prefix]
              prefixed_xml.add_namespace_prefix(nil)
            end

            xml_mapping.attributes.each do |attribute_rule|
              attribute_rule.serialize_attribute(element, prefixed_xml.parent,
                                                 xml)
            end

            current_namespace = xml_mapping.namespace_uri
            child_options = options.merge({ parent_namespace: current_namespace })

            # Propagate use_prefix option to children
            if @options && @options.key?(:use_prefix)
              child_options[:use_prefix] = @options[:use_prefix]
            end

            # Pass namespace_scope xmlns declarations to nested elements
            if attributes && attributes.any? { |k, _| k.start_with?("xmlns:") }
              child_options[:parent_namespace_scope_attrs] = attributes.select { |k, _| k.start_with?("xmlns:") }
            end

            # Pass declared_namespaces registry to children
            child_options[:declared_namespaces] = options[:declared_namespaces]

            mappings = xml_mapping.elements + [xml_mapping.raw_mapping].compact
            mappings.each do |element_rule|
              attribute_def = attribute_definition_for(element, element_rule,
                                                       mapper_class: mapper_class)

              next if child_options[:except]&.include?(element_rule.to)

              if attribute_def
                value = attribute_value_for(element, element_rule)

                next if !element_rule.render?(value, element)

                value = attribute_def.build_collection(value) if attribute_def.collection? && !attribute_def.collection_instance?(value)
              end

              add_to_xml(
                prefixed_xml,
                element,
                element_rule.prefix,
                value,
                child_options.merge({ attribute: attribute_def, rule: element_rule,
                                      mapper_class: mapper_class }),
              )
            end

            process_content_mapping(element, xml_mapping.content_mapping,
                                    prefixed_xml, mapper_class)
          end
        end

        def process_content_mapping(element, content_rule, xml, mapper_class)
          return unless content_rule

          if content_rule.custom_methods[:to]
            mapper_class.new.send(
              content_rule.custom_methods[:to],
              element,
              xml.parent,
              xml,
            )
          else
            text = content_rule.serialize(element)
            text = text.join if text.is_a?(Array)

            xml.add_text(xml, text, cdata: content_rule.cdata)
          end
        end

        def ordered?(element, options = {})
          return false unless element.respond_to?(:element_order)
          return element.ordered? if element.respond_to?(:ordered?)
          return options[:mixed_content] if options.key?(:mixed_content)

          mapper_class = options[:mapper_class]
          mapper_class ? mapper_class.mappings_for(:xml).mixed_content? : false
        end

        def set_namespace?(rule)
          rule.nil? || !rule.namespace_set?
        end

        def render_element?(rule, element, value)
          rule.render?(value, element)
        end

        def render_default?(rule, element)
          !element.respond_to?(:using_default?) ||
            rule.render_default? ||
            !element.using_default?(rule.to)
        end

        def build_namespace_attributes(klass, processed = {}, options = {})
          xml_mappings = klass.mappings_for(:xml)
          attributes = klass.attributes
          parent_namespace = options[:parent_namespace]
          is_root_call = options[:is_root_call]
          namespace_scope = xml_mappings.namespace_scope

          attrs = {}

          if xml_mappings.namespace_uri && set_namespace?(options[:caller_rule]) && is_root_call != false
            should_add_xmlns = parent_namespace.nil? || parent_namespace != xml_mappings.namespace_uri

            if should_add_xmlns
              # Check if we should use prefix based on options
              use_prefix = if options.key?(:use_prefix)
                            options[:use_prefix]
                          elsif options.key?(:namespace_prefix)
                            # Legacy option: namespace_prefix means use prefix
                            true
                          end

              prefixed_name = if use_prefix
                                ["xmlns", xml_mappings.namespace_prefix].compact.join(":")
                              else
                                "xmlns"  # Default namespace
                              end

              attrs[prefixed_name] = xml_mappings.namespace_uri
            end
          end

          # When at root level and namespace_scope is defined, collect all namespace URIs
          # that should be declared at root
          if is_root_call != false && xml_mappings.namespace_scope_config&.any?
            # Enhanced: Add namespaces from scope with :always declaration mode
            xml_mappings.namespace_scope_config.each do |ns_config|
              ns_class = ns_config[:namespace]
              declare_mode = ns_config[:declare]

              next unless ns_class.respond_to?(:uri) && ns_class.respond_to?(:prefix_default)

              ns_uri = ns_class.uri
              ns_prefix = ns_class.prefix_default

              next if ns_uri.nil? || ns_prefix.nil?
              next if attrs.value?(ns_uri) # Already added

              # For :always mode, add namespace even if unused
              # For :auto mode (default), it will be added later if used
              if declare_mode == :always
                attrs["xmlns:#{ns_prefix}"] = ns_uri
              end
            end
          end

          xml_mappings.mappings.each do |mapping_rule|
            processed[klass] ||= {}

            next if processed[klass][mapping_rule.name]

            processed[klass][mapping_rule.name] = true

            type = if mapping_rule.delegate
                     attributes[mapping_rule.delegate].type(register)
                       .attributes[mapping_rule.to].type(register)
                   else
                     attributes[mapping_rule.to]&.type(register)
                   end

            next unless type

            if type <= Lutaml::Model::Serialize
              child_options = {
                caller_rule: mapping_rule,
                parent_namespace: xml_mappings.namespace_uri || parent_namespace,
                is_root_call: false, # Mark that we're recursing
              }

              attrs = attrs.merge(build_namespace_attributes(type, processed,
                                                             child_options))
            end

            # Only add namespace declaration if NOT in namespace_scope (will be declared locally)
            if mapping_rule.namespace && mapping_rule.prefix && mapping_rule.name != "lang"
              # Check if this namespace is in scope using helper method
              in_scope = namespace_in_scope?(mapping_rule.namespace, namespace_scope)

              # Only add if not in scope or if we're not at root level
              unless in_scope && is_root_call != false
                attrs["xmlns:#{mapping_rule.prefix}"] = mapping_rule.namespace
              end
            end
          end

          attrs
        end

        def build_attributes(element, xml_mapping, options = {})
          parent_namespace = options[:parent_namespace]
          # Extract namespace classes from scope config (handles both Class and Hash formats)
          namespace_scope = xml_mapping.namespace_scope

          # Determine use_prefix from options or @options (root level)
          use_prefix = options[:use_prefix] || @options&.[](:use_prefix)

          attrs = if options.fetch(:set_namespace, true)
                    namespace_attributes(xml_mapping, parent_namespace, use_prefix)
                  else
                    {}
                  end

          # Merge in any options-based use_prefix setting
          if use_prefix && xml_mapping.namespace_uri
            # When use_prefix is true, ensure prefixed namespace is declared
            if !attrs.values.include?(xml_mapping.namespace_uri)
              attrs["xmlns:#{xml_mapping.namespace_prefix}"] = xml_mapping.namespace_uri
            end
          end

          # When this element's namespace differs from parent, and parent has namespace_scope,
          # ensure those xmlns declarations are available for this and any nested elements
          if options[:parent_namespace_scope_attrs] && xml_mapping.namespace_uri != parent_namespace
            # For nested elements with different namespace from parent:
            # If this element's namespace was declared in parent's namespace_scope,
            # we MUST include that xmlns declaration on this element for Nokogiri to use xml[prefix]

            # Track what's already declared to avoid redundancy
            declared_ns = options[:declared_namespaces] || {}

            options[:parent_namespace_scope_attrs].each do |ns_key, ns_uri|
              # Skip if this namespace prefix is already declared in ancestor
              # AND the namespace URI matches (same prefix+URI combo)
              prefix_name = ns_key.sub("xmlns:", "")
              next if declared_ns[prefix_name] == ns_uri

              # Add if this element's own namespace matches
              # This is CRITICAL for Nokogiri xml[prefix] to work
              if ns_uri == xml_mapping.namespace_uri
                attrs[ns_key] = ns_uri unless attrs.key?(ns_key)
              end
            end
          end

          # Enhanced: Add namespaces from scope with :always declaration mode
          # This ensures namespaces are declared at root level even if unused
          if xml_mapping.namespace_scope_config&.any?
            xml_mapping.namespace_scope_config.each do |ns_config|
              ns_class = ns_config[:namespace]
              declare_mode = ns_config[:declare]

              next unless ns_class.respond_to?(:uri) && ns_class.respond_to?(:prefix_default)

              ns_uri = ns_class.uri
              ns_prefix = ns_class.prefix_default

              next if ns_uri.nil? || ns_prefix.nil?
              next if attrs.value?(ns_uri) # Already added

              # For :always mode, add namespace even if unused
              # For :auto mode (default), it will be added later if used
              if declare_mode == :always
                attrs["xmlns:#{ns_prefix}"] = ns_uri
              end
            end
          end

          if element.respond_to?(:schema_location) && element.schema_location.is_a?(Lutaml::Model::SchemaLocation) && !options[:except]&.include?(:schema_location)
            attrs.merge!(element.schema_location.to_xml_attributes)
          end

          xml_mapping.attributes.each_with_object(attrs) do |mapping_rule, hash|
            next if mapping_rule.custom_methods[:to] || options[:except]&.include?(mapping_rule.to)

            mapping_rule_name = mapping_rule.multiple_mappings? ? mapping_rule.name.first : mapping_rule.name

            # Resolve namespace for attribute
            attr = attribute_definition_for(element, mapping_rule,
                                            mapper_class: options[:mapper_class])
            ns_info = resolve_attribute_namespace(mapping_rule, attr, options)

            # Add namespace declaration if needed (check namespace_scope)
            if ns_info[:uri] && ns_info[:prefix] && mapping_rule_name != "lang"
              # Check if namespace is in scope (should be declared at root)
              in_scope = namespace_in_scope?(ns_info[:uri], namespace_scope)
              hash["xmlns:#{ns_info[:prefix]}"] = ns_info[:uri] unless in_scope
            elsif mapping_rule.namespace && mapping_rule.prefix && mapping_rule_name != "lang"
              in_scope = namespace_in_scope?(mapping_rule.namespace,
                                             namespace_scope)
              unless in_scope
                hash["xmlns:#{mapping_rule.prefix}"] = mapping_rule.namespace
              end
            end

            value = mapping_rule.to_value_for
            value = attr.serialize(value, :xml, register) if attr

            value = ExportTransformer.call(value, mapping_rule, attr)

            value = value&.join(mapping_rule.delimiter) if mapping_rule.delimiter
            value = mapping_rule.as_list[:export].call(value) if mapping_rule.as_list && mapping_rule.as_list[:export]

            if render_element?(mapping_rule, element, value)
              # Use resolved prefix if available
              attr_name = if ns_info[:prefix]
                            "#{ns_info[:prefix]}:#{mapping_rule_name}"
                          else
                            mapping_rule.prefixed_name
                          end
              hash[attr_name] = value ? value.to_s : value
            end
          end

          xml_mapping.elements.each_with_object(attrs) do |mapping_rule, hash|
            next if options[:except]&.include?(mapping_rule.to)

            # Resolve namespace for element
            attr = attribute_definition_for(element, mapping_rule,
                                            mapper_class: options[:mapper_class])
            ns_info = resolve_element_namespace(mapping_rule, attr, options)

            # Add namespace declaration if needed (check namespace_scope)
            if ns_info[:uri] && ns_info[:prefix]
              in_scope = namespace_in_scope?(ns_info[:uri], namespace_scope)

              # NEW LOGIC: If in namespace_scope with :auto mode, ADD xmlns here (it's being used)
              # If NOT in namespace_scope, always add (local declaration)
              if in_scope
                # Check if this is :auto mode in namespace_scope_config
                scope_entry = xml_mapping.namespace_scope_config&.find do |cfg|
                  ns_class = cfg[:namespace]
                  ns_class.respond_to?(:uri) && ns_class.uri == ns_info[:uri]
                end

                # If :auto mode (default), declare now since namespace is being used
                if scope_entry && scope_entry[:declare] == :auto
                  hash["xmlns:#{ns_info[:prefix]}"] = ns_info[:uri]
                end
                # If :always mode, already declared at root (line 412), don't redeclare
                # If :never mode, skip (error case)
              else
                # Not in scope, always declare locally
                hash["xmlns:#{ns_info[:prefix]}"] = ns_info[:uri]
              end
            elsif mapping_rule.namespace && mapping_rule.prefix
              in_scope = namespace_in_scope?(mapping_rule.namespace,
                                             namespace_scope)
              unless in_scope
                hash["xmlns:#{mapping_rule.prefix}"] = mapping_rule.namespace
              end
            end
          end
        end

        def attribute_definition_for(element, rule, mapper_class: nil)
          klass = mapper_class || element.class
          return klass.attributes[rule.to] unless rule.delegate

          delegated_obj = element.send(rule.delegate)
          return nil if delegated_obj.nil?

          delegated_obj.class.attributes[rule.to]
        end

        def attribute_value_for(element, rule)
          return element.send(rule.to) unless rule.delegate

          element.send(rule.delegate).send(rule.to)
        end

        def namespace_attributes(xml_mapping, parent_namespace = nil, use_prefix = nil)
          return {} unless xml_mapping.namespace_uri
          return {} if parent_namespace == xml_mapping.namespace_uri

          # use_prefix is passed as parameter (from options or @options)
          attrs = {}

          if use_prefix
            # Prefixed namespace only
            attrs["xmlns:#{xml_mapping.namespace_prefix}"] = xml_mapping.namespace_uri
          else
            # Default namespace
            attrs["xmlns"] = xml_mapping.namespace_uri

            # ALSO add prefixed declaration if child elements might need it
            # This happens when:
            # 1. element_form_default is :qualified, OR
            # 2. ANY element has explicit form: :qualified
            needs_prefix = xml_mapping.namespace_class&.element_form_default == :qualified ||
                          xml_mapping.elements.any?(&:qualified?)

            if needs_prefix && xml_mapping.namespace_prefix
              attrs["xmlns:#{xml_mapping.namespace_prefix}"] = xml_mapping.namespace_uri
            end
          end

          attrs
        end

        def self.type
          Utils.snake_case(self).split("/").last.split("_").first
        end

        def self.order_of(element)
          element.order
        end

        def self.name_of(element)
          element.name
        end

        def self.text_of(element)
          element.text
        end

        def self.namespaced_name_of(element)
          element.namespaced_name
        end

        def text
          return @root.text_children.map(&:text) if @root.children.count > 1

          @root.text
        end

        def cdata
          @root.cdata
        end

        private

        def setup_register(register)
          return register if register.is_a?(Symbol)

          return_register = if register.is_a?(Lutaml::Model::Register)
                              register.id
                            elsif @root.respond_to?(:__register)
                              @root.__register
                            elsif @root.instance_variable_defined?(:@__register)
                              @root.instance_variable_get(:@__register)
                            end
          return_register || Lutaml::Model::Config.default_register
        end

        def determine_mapper_class(element, options)
          if options[:mapper_class] && element.is_a?(options[:mapper_class])
            element.class
          else
            options[:mapper_class] || element.class
          end
        end

        def determine_namespace_prefix(options, mapping)
          # NEW: :use_prefix is a boolean flag
          if options.key?(:use_prefix)
            return options[:use_prefix] ? mapping.namespace_prefix : nil
          end

          # Legacy: check for namespace_prefix option (direct prefix value)
          return options[:namespace_prefix] if options.key?(:namespace_prefix)

          # BREAKING CHANGE: Default to nil (default namespace) instead of
          # using mapping.namespace_prefix. Users must pass use_prefix: true
          # to get prefixed output.
          nil
        end

        def build_element_attributes(element, mapping, options)
          xml_attributes = options[:xml_attributes] ||= {}
          attributes = build_attributes(element, mapping, options)

          parent_namespace = options[:parent_namespace]
          element_namespace = mapping.namespace_uri

          merged_attrs = attributes.dup
          xml_attributes.each do |key, value|
            next if (key == "xmlns" || key.start_with?("xmlns:")) &&
              (parent_namespace == element_namespace || merged_attrs.key?(key))

            merged_attrs[key] = value
          end

          merged_attrs&.compact
        end

        # Resolve namespace for element using MappingRule.resolve_namespace
        #
        # @param rule [MappingRule] the mapping rule
        # @param attribute [Attribute] the attribute being mapped
        # @param options [Hash] serialization options
        # @return [Hash] namespace info { uri:, prefix:, ns_class: }
        def resolve_element_namespace(rule, attribute, options = {})
          return { uri: nil, prefix: nil, ns_class: nil } unless rule

          parent_ns_uri = options[:parent_namespace]
          mapper_class = options[:mapper_class]

          # Try to get parent namespace class if available
          parent_ns_class = if mapper_class.respond_to?(:mappings_for)
                              mapper_class.mappings_for(:xml)&.namespace_class
                            end

          # Default form is unqualified unless specified
          form_default = :unqualified

          # Pass use_prefix from options to enable prefix: true behavior
          # Check both @options (root level) and options hash (propagated to children)
          use_prefix_option = options[:use_prefix] || @options&.[](:use_prefix)

          rule.resolve_namespace(
            attr: attribute,
            register: register,
            parent_ns_uri: parent_ns_uri,
            parent_ns_class: parent_ns_class,
            form_default: form_default,
            use_prefix: use_prefix_option,
          )
        end

        # Resolve namespace for attribute using MappingRule.resolve_namespace
        #
        # @param rule [MappingRule] the mapping rule
        # @param attribute [Attribute] the attribute being mapped
        # @param options [Hash] serialization options
        # @return [Hash] namespace info { uri:, prefix:, ns_class: }
        def resolve_attribute_namespace(rule, attribute, _options = {})
          return { uri: nil, prefix: nil, ns_class: nil } unless rule

          # Attributes don't inherit parent namespace per W3C
          rule.resolve_namespace(
            attr: attribute,
            register: register,
            parent_ns_uri: nil,
            parent_ns_class: nil,
            form_default: :unqualified,
          )
        end

        # Check if a namespace URI is in the namespace_scope
        #
        # @param namespace_uri [String] the namespace URI to check
        # @param namespace_scope [Array<Class, Hash>] array of XmlNamespace classes or Hash configs
        # @return [Boolean] true if namespace is in scope
        def namespace_in_scope?(namespace_uri, namespace_scope)
          return false unless namespace_scope&.any?

          namespace_scope.any? do |ns_entry|
            # Handle both Class and Hash formats
            ns_class = if ns_entry.is_a?(Hash)
                         ns_entry[:namespace]
                       else
                         ns_entry
                       end

            ns_class.respond_to?(:uri) && ns_class.uri == namespace_uri
          end
        end
      end
    end
  end
end
