# frozen_string_literal: true

module Lutaml
  module Xml
    # ModelTransform is the XML transform handler for the model layer.
    # It inherits from Lutaml::Model::Transform and implements XML-specific
    # data_to_model and model_to_data methods.
    #
    # This class bridges the model layer and the XML module:
    # - Inherits from Lutaml::Model::Transform (model's format-agnostic base)
    # - Delegates to Lutaml::Xml::Transformation for actual XML serialization
    # - Used by model's serialization pipeline via Transform.for(:xml)
    #
    class ModelTransform < ::Lutaml::Model::Transform
      # Performance: Frozen empty hash to reduce allocations
      EMPTY_HASH = {}.freeze

      def data_to_model(data, _format, options = {})
        if model_class.include?(::Lutaml::Model::Serialize)
          instance = model_class.new({ __register: __register })
        else
          instance = model_class.new
          register_accessor_methods_for(instance, __register)
        end
        root_and_parent_assignment(instance, options)
        apply_xml_mapping(data, instance, options)
      end

      def model_to_data(model, _format, options = {})
        # Check if model class has a pre-compiled transformation
        model_class = model.class
        if model_class.is_a?(Class) && model_class.include?(::Lutaml::Model::Serialize)
          transformation = model_class.transformation_for(:xml, __register)

          # If transformation exists and is an Xml::Transformation, use it
          if transformation.is_a?(::Lutaml::Xml::Transformation)
            return transformation.transform(model, options)
          end
        end

        # Fallback to returning model for classes without transformation
        model
      end

      private

      def apply_xml_mapping(doc, instance, options = {})
        # Performance: Cache frequently accessed options in local variables
        mappings = options[:mappings] || mappings_for(:xml).mappings
        default_namespace = options[:default_namespace]
        ordered_option = options[:ordered]
        mixed_content_option = options[:mixed_content]
        encoding = options[:encoding]
        doctype = options[:doctype]

        instance.encoding = encoding
        instance.doctype = doctype if doctype

        # Transfer XML declaration info if present (Issue #1)
        if doc.respond_to?(:xml_declaration) && doc.xml_declaration
          instance.instance_variable_set(:@xml_declaration, doc.xml_declaration)
        end

        # Transfer input namespaces if present (Issue #3: Namespace Preservation)
        if doc.is_a?(::Lutaml::Xml::InputNamespacesCapable) && doc.input_namespaces&.any?
          instance.instance_variable_set(:@__input_namespaces,
                                         doc.input_namespaces)
        end

        return instance unless doc

        validate_document!(doc, options)

        set_instance_ordering(instance, doc, ordered_option,
                              mixed_content_option)
        set_schema_location(instance, doc)

        defaults_used = []

        # Performance: Get namespace_uri once if needed for default_namespace
        xml_mapping = mappings_for(:xml)
        namespace_uri = xml_mapping&.namespace_uri

        mappings.each do |rule|
          # Performance: Cache rule properties accessed multiple times
          rule.name
          rule_to = rule.to
          rule_namespace_set = rule.namespace_set?
          rule_namespace_param = rule_namespace_set ? rule.instance_variable_get(:@namespace_param) : nil

          attr = attribute_for_rule(rule)
          next if attr&.derived?

          raise "Attribute '#{rule_to}' not found in #{context}" unless valid_rule?(
            rule, attr
          )

          # Performance: Only create new_opts when we need to override default_namespace
          # Avoid dup for the common case where namespace is not set
          new_opts = if rule_namespace_set && rule_namespace_param != :inherit
                       { default_namespace: rule.namespace }
                     elsif default_namespace.nil? && namespace_uri
                       { default_namespace: namespace_uri }
                     else
                       options
                     end

          value = if rule.raw_mapping?
                    doc.root.inner_xml
                  elsif rule.content_mapping?
                    rule.cdata ? doc.cdata : doc.text
                  else
                    # Performance: Pass cached attr to avoid recomputing attribute_for_rule
                    val = value_for_rule(doc, rule, new_opts, instance, attr)

                    if (val.nil? || ::Lutaml::Model::Utils.uninitialized?(val)) &&
                        (instance.using_default?(rule_to) || rule.render_default)
                      defaults_used << rule_to
                      attr&.default(__register) || rule.to_value_for(instance)
                    else
                      val
                    end
                  end

          from_map = rule.value_map(:from, new_opts)
          value = apply_value_map(value, from_map, attr)
          value = normalize_xml_value(value, rule, attr, new_opts)
          value = rule.transform_value(attr, value, :from, :xml)
          rule.deserialize(instance, value, attributes, context)
        end

        defaults_used.each do |attr_name|
          instance.using_default_for(attr_name)
        end

        # CRITICAL: Create DeclarationPlan AFTER model is fully populated
        # This captures WHERE namespaces were declared and in WHAT format
        # The plan will be used during serialization to preserve the original structure
        if model_class.is_a?(Class) && model_class.include?(::Lutaml::Model::Serialize)
          mapping = model_class.mappings_for(:xml, __register)
          # Check if doc responds to input_namespaces (handles nested elements that are OxElement)
          # CRITICAL: Collect input_namespaces from ALL elements with LOCATION info
          # This preserves WHERE each namespace was declared, not just WHAT was declared
          namespaces_with_locations = collect_input_namespaces_with_locations(doc)
          if mapping && namespaces_with_locations&.any?
            # Create plan from input namespaces with location info (format + location preservation)
            plan = ::Lutaml::Xml::DeclarationPlan.from_input_with_locations(
              namespaces_with_locations,
              mapping,
            )

            # Store plan in instance for use during serialization
            if instance.respond_to?(:__input_declaration_plan=)
              instance.__input_declaration_plan = plan
            end
          end
        end

        instance
      end

      # Collect input_namespaces from all elements in the document tree
      #
      # Namespaces can be declared on any element, not just the root.
      # We need to collect them all for proper format preservation.
      #
      # @param element [XmlElement] The element to collect from
      # @param visited [Set] Set of visited elements to prevent cycles
      # @return [Hash] Merged namespace info from all elements
      def collect_all_input_namespaces(element, visited = Set.new)
        # Performance: Early return for nil
        return EMPTY_HASH unless element
        # Prevent infinite recursion for circular references
        return EMPTY_HASH if visited.include?(element.object_id)

        visited.add(element.object_id)

        # Performance: Get own namespaces first
        # Note: Using is_a?(InputNamespacesCapable) because both Document and Element classes include the marker
        own_ns = if element.is_a?(::Lutaml::Xml::InputNamespacesCapable) && element.input_namespaces
                   element.input_namespaces
                 end

        # Performance: Early return if no children to recurse
        # All XmlElement subclasses have children method
        children = element.respond_to?(:children) ? element.children : []
        if children.empty?
          return own_ns || EMPTY_HASH
        end

        # Start with own namespaces
        namespaces = own_ns ? own_ns.dup : {}

        # Recursively collect from children (use cached children variable)
        children.each do |child|
          next if child.is_a?(String) # Skip text nodes

          child_namespaces = collect_all_input_namespaces(child, visited)
          # Merge, but don't overwrite (first declaration wins)
          child_namespaces.each do |key, value|
            namespaces[key] ||= value
          end
        end

        namespaces
      end

      # Collect input_namespaces WITH their declaration locations
      #
      # Returns a tree structure mapping element paths to namespace declarations.
      # This enables preservation of WHERE each namespace was declared, not just WHAT was declared.
      #
      # @param element [XmlElement] The element to collect from
      # @param path [Array<String>] Current element path (array of element names)
      # @param result [Hash] Accumulated result { path => namespaces }
      # @param visited [Set] Set of visited elements to prevent cycles
      # @return [Hash] Location-aware namespace info { path_array => namespace_hash }
      def collect_input_namespaces_with_locations(element, path = [],
result = {}, visited = Set.new)
        return result unless element
        return result if visited.include?(element.object_id)

        visited.add(element.object_id)

        # Get namespaces declared on THIS element only
        # Note: Using is_a?(InputNamespacesCapable) because both Document and Element classes include the marker
        own_ns = if element.is_a?(::Lutaml::Xml::InputNamespacesCapable) && element.input_namespaces
                   element.input_namespaces
                 end

        # Store if this element has namespace declarations
        if own_ns&.any?
          result[path] = own_ns
        end

        # Recurse into children - all XmlElement subclasses have children
        element.children.each do |child|
          next if child.is_a?(String) # Skip text nodes

          # All XmlElement subclasses have name method
          child_name = child.is_a?(::Lutaml::Xml::XmlElement) ? child.name.to_s : "unknown"
          child_path = path + [child_name]
          collect_input_namespaces_with_locations(child, child_path, result,
                                                  visited)
        end

        result
      end

      def validate_document!(doc, options)
        return unless doc.is_a?(Array)

        raise ::Lutaml::Model::CollectionTrueMissingError(
          context,
          options[:caller_class],
        )
      end

      def set_instance_ordering(instance, doc, ordered_option,
mixed_content_option)
        return unless instance.respond_to?(:ordered=)

        instance.element_order = doc.root.order
        instance.ordered = mappings_for(:xml).ordered? || ordered_option
        instance.mixed = mappings_for(:xml).mixed_content? || mixed_content_option
      end

      def set_schema_location(instance, doc)
        schema_location = doc.attributes.values.find do |a|
          a.unprefixed_name == "schemaLocation"
        end

        return if schema_location.nil?

        # Store raw schemaLocation string as metadata
        # SchemaLocation class is for programmatic creation with XmlNamespace classes only
        # When parsing XML, we just preserve the string value as-is
        instance.instance_variable_set(:@raw_schema_location,
                                       schema_location.value)
      end

      def value_for_xml_attribute(doc, rule, rule_names)
        # For attributes, rule_names may contain namespaced names, but find_attribute_value
        # expects prefix:name or just name, so we need to convert namespaced names to prefix format.
        #
        # Namespaced name formats:
        # - URI format: "http://.../namespace:attr" or "urn:...:attr"
        # - Simple prefix format: "my-ns:attr" (namespace URI is a simple string, not a URI)
        # - Unprefixed: "attr" (no namespace)
        attribute_names = rule_names.filter_map do |rn|
          converted = convert_rule_name_to_attribute_name(doc, rn)
          converted || rn
        end

        value = doc.root.find_attribute_value(attribute_names)

        # Fallback: if value is nil, try to match by local name only.
        # This handles the case where the namespace prefix is not declared in the document
        # (e.g., v:ext without xmlns:v="...").
        if value.nil? && rule_names.any? { |rn| rn.include?(":") }
          value = find_attribute_by_local_name(doc, rule_names)
        end

        value = value&.split(rule.delimiter) if rule.delimiter

        value = rule.as_list[:import].call(value) if rule.as_list && rule.as_list[:import]

        value
      end

      # Convert a rule name (URI:localname or prefix:localname) to an attribute name
      # that can be used to find the attribute in the document.
      #
      # @param doc [XmlElement] the parsed XML document root
      # @param rule_name [String] the rule name (e.g., "urn:...:ext", "http://.../ns:val", "my-ns:val")
      # @return [String, nil] the attribute name to look up, or nil if no conversion needed
      def convert_rule_name_to_attribute_name(doc, rule_name)
        return nil unless rule_name.include?(":")

        # Split on last colon to get namespace/localname
        # This correctly handles URIs with colons (http://... or urn:...)
        last_colon_index = rule_name.rindex(":")
        namespace_part = rule_name[0...last_colon_index]
        local_name = rule_name[(last_colon_index + 1)..]

        # Determine if namespace_part is a URI format or a simple prefix
        # URI formats: contains "://" (http/https) or starts with "urn:"
        is_uri_format = namespace_part.include?("://") || namespace_part.start_with?("urn:")

        if is_uri_format
          # URI format: look up attribute by namespace URI and local name
          doc.root.attributes.values.find do |attr|
            attr.namespace == namespace_part && attr.unprefixed_name == local_name
          end&.name
        else
          # Simple prefix format: look up the actual prefix from document's namespace declarations
          # The namespace_part is the namespace URI declared in the document (e.g., "my-ns").
          # Find the corresponding prefix (e.g., "my") and build "my:val".
          ns_data = doc.root.namespaces.values.find { |nd| nd.uri == namespace_part }
          return nil unless ns_data&.prefix

          "#{ns_data.prefix}:#{local_name}"
        end
      end

      # Fallback: find attribute by local name only when namespace prefix is unresolved.
      #
      # @param doc [XmlElement] the parsed XML document root
      # @param rule_names [Array<String>] the rule names to match
      # @return [String, nil] the attribute value or nil
      def find_attribute_by_local_name(doc, rule_names)
        rule_names.each do |rn|
          next unless rn.include?(":")

          last_colon_index = rn.rindex(":")
          local_name = rn[(last_colon_index + 1)..]

          matched_attr = doc.root.attributes.values.find do |attr|
            # Match by the attribute's namespaced_name, unprefixed_name, or by extracting
            # local name from the attribute's key (handles unresolved prefixes).
            attr.namespaced_name == local_name ||
              attr.unprefixed_name == local_name ||
              (attr.namespace.nil? && attr.name.split(":").last == local_name)
          end
          return matched_attr&.value if matched_attr
        end
        nil
      end

      def value_for_rule(doc, rule, options, instance, cached_attr = nil)
        # Performance: Use cached attr from caller if available
        attr = cached_attr || attribute_for_rule(rule)
        attr_type = attr&.type(__register)

        # Performance: Cache rule properties accessed in hot loop
        rule_name_str = rule.name.to_s
        rule_namespace_set = rule.namespace_set?
        rule_namespace_param = rule_namespace_set ? rule.instance_variable_get(:@namespace_param) : nil
        rule_prefix_param = rule_namespace_set ? rule.instance_variable_get(:@prefix_param) : nil
        rule_namespace = rule_namespace_set ? rule.namespace : nil
        options[:default_namespace]

        # Enhanced namespace resolution with type support
        rule_names = resolve_rule_names_with_type(rule, attr, options)

        return value_for_xml_attribute(doc, rule, rule_names) if rule.attribute?

        # Performance: Pre-compute type-related values used in the hot loop
        attr_type_is_serializable = attr_type && attr_type <= ::Lutaml::Model::Serialize
        attr_type_is_class = attr_type.is_a?(Class) && attr_type.include?(::Lutaml::Model::Serialize)

        # Pre-compute namespace class for prefix matching (only needed if attr_type is Serializable)
        nil
        type_ns_prefix_str = nil
        if attr_type_is_serializable
          type_ns_class = if attr_type_is_class
                            attr_type.mappings_for(:xml)&.namespace_class
                          else
                            attr.type_namespace_class(__register)
                          end
          type_ns_prefix_str = type_ns_class&.prefix_default&.to_s
        end

        children = doc.children.select do |child|
          next false if child.is_a?(String)

          # Handle XmlElement children with text? method
          # Performance: All XML adapter children inherit from XmlElement
          next false if child.is_a?(::Lutaml::Xml::XmlElement) && child.text?

          # Handle explicit namespace: nil with prefix: nil
          # When both namespace: nil and prefix: nil are set, this means "no namespace constraint"
          # The child element can declare its own namespace and should still match by local name
          if rule_namespace_set && rule_namespace.nil? &&
              rule_namespace_param.nil? && rule_prefix_param.nil?
            # Match by unprefixed name only, regardless of child's namespace
            next child.unprefixed_name == rule_name_str
          end

          # First try exact namespace match
          next true if rule_names.include?(child.namespaced_name)

          # Second: try to match by prefix when child has xmlns="" (explicit blank namespace)
          # This handles the case where elements have prefixed names but are in blank namespace
          # e.g., <GML:ApplicationSchema xmlns=""> should match the rule expecting GML namespace
          child_ns_prefix = child.namespace_prefix
          # Match by prefix AND local name to avoid matching unrelated elements
          # with the same namespace prefix (e.g., xsd:attributeGroup should not
          # match a rule for xsd:attribute)
          if child_ns_prefix && attr_type_is_serializable && type_ns_prefix_str && child_ns_prefix == type_ns_prefix_str &&
              child.unprefixed_name == rule_name_str
            next true
          end

          # Fallback: if the child has a different namespace and attr_type is Serializable,
          # match by unprefixed name (child declares its own namespace)
          #
          # CRITICAL: Only use fallback for unqualified children (no prefix).
          # Children with explicit prefixes should NOT match via fallback, even if xmlns="" is set.
          # This ensures that GML:ApplicationSchema doesn't match CityGML:ApplicationSchema just because
          # they have the same unprefixed name.
          if attr_type_is_serializable
            # Only match by unprefixed name if child doesn't have an explicit namespace prefix
            # This prevents cross-namespace matching when elements have the same local name
            !child_ns_prefix && rule_names.any? do |rn|
              rn.split(":").last == child.unprefixed_name
            end
          else
            false
          end
        end

        if rule.has_custom_method_for_deserialization? || attr_type == ::Lutaml::Model::Type::Hash
          return_child = attr_type == ::Lutaml::Model::Type::Hash || !attr.collection? if attr
          return return_child ? children.first : children
        end

        return handle_cdata(children) if rule.cdata
        return ::Lutaml::Model::UninitializedClass.instance if children.empty?

        values = attr.build_collection

        instance.value_set_for(attr.name)

        children.each do |child|
          if !rule.has_custom_method_for_deserialization? && attr_type_is_serializable
            cast_options = options.except(:mappings)
            cast_options[:polymorphic] = rule.polymorphic if rule.polymorphic
            cast_options[:register] = __register
            cast_options[:__parent] = instance
            cast_options[:__root] = instance.__root || instance

            # Namespace-aware type resolution: extract namespace URI from child
            if child.is_a?(::Lutaml::Xml::XmlElement)
              child_namespace_uri = child.namespace_uri
              if child_namespace_uri
                cast_options[:namespace_uri] =
                  child_namespace_uri
              end
            end

            values << attr.cast(child, :xml, __register, cast_options)
          elsif attr.raw?
            values << inner_xml_of(child)
          else
            return nil if rule.render_nil_as_nil? && child.nil_element?

            text = child.nil_element? ? nil : (child&.text&.+ child&.cdata)
            values << text
          end
        end

        normalized_value_for_attr(values, attr)
      end

      def handle_cdata(children)
        values = children.map do |child|
          child.cdata_children&.map(&:text)
        end.flatten

        children.count > 1 ? values : values.first
      end

      def normalized_value_for_attr(values, attr)
        # for xml collection: true cases like
        #   <store><items /></store>
        #   <store><items xsi:nil="true"/></store>
        #   <store><items></items></store>
        #
        # these are considered empty collection
        return [] if attr&.collection? && [[nil], [""]].include?(values)
        return values if attr&.collection?

        values.is_a?(Array) ? values.first : values
      end

      def normalize_xml_value(value, rule, attr, options = {})
        collection_class = attr&.collection_class || Array
        value = [value].compact if !value.nil? && attr&.collection? && !value.is_a?(collection_class)

        return value unless cast_value?(attr, rule)

        attr.cast(value, :xml, __register, options)
      end

      def cast_value?(attr, rule)
        attr && rule.castable?
      end

      def ensure_utf8(value)
        case value
        when String
          value.encode("UTF-8", invalid: :replace, undef: :replace,
                                replace: "")
        when Array
          value.map { |v| ensure_utf8(v) }
        when ::Hash
          value.transform_keys do |k|
            ensure_utf8(k)
          end.transform_values do |v|
            ensure_utf8(v)
          end
        else
          value
        end
      end

      def inner_xml_of(node)
        case node
        when ::Lutaml::Xml::DataModel::XmlElement
          node.inner_xml
        else
          node.children.map(&:to_xml).join
        end
      end

      # Resolve rule names with type namespace support
      #
      # @param rule [MappingRule] the mapping rule
      # @param attr [Attribute, nil] the attribute
      # @param options [Hash] options including default_namespace
      # @return [Array<String>] possible namespaced names for matching
      def resolve_rule_names_with_type(rule, attr, options)
        # If rule has explicit namespace or no type namespace, use standard logic
        if rule.namespace_set? || !attr
          return rule.namespaced_names(options[:default_namespace])
        end

        # Check if attribute type has namespace
        type_ns_uri = attr.type_namespace_uri(__register)

        if type_ns_uri
          # Use type namespace URI for matching (child.namespaced_name uses URI:localname format)
          ["#{type_ns_uri}:#{rule.name}"]
        else
          # Use existing logic
          rule.namespaced_names(options[:default_namespace])
        end
      end
    end
  end
end
