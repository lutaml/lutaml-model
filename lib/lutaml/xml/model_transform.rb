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
        # Use child's own default register if it has one
        # This ensures versioned schemas (e.g., MML v2 with lutaml_default_register = :mml_v2)
        # are instantiated with their native context
        child_register = Lutaml::Model::Utils.resolve_child_register(
          model_class, lutaml_register
        )

        if model_class.include?(::Lutaml::Model::Serialize)
          instance = model_class.new({ lutaml_register: child_register })
        else
          instance = model_class.new
          register_accessor_methods_for(instance, child_register)
        end
        # Set @__xml_namespace_prefix on root model for doubly-defined namespace support.
        # This is read during serialization to determine if the root element should use
        # an explicit prefix from the input XML.
        # Check the XmlElement's namespace_prefix (not the model's):
        # - Nil/empty: root uses default format (doubly-defined case)
        # - Set: root has explicit prefix (mixed content case)
        root_element = if data.is_a?(::Lutaml::Xml::XmlElement)
                         data
                       elsif data.respond_to?(:root)
                         data.root
                       end
        if root_element && instance.is_a?(::Lutaml::Model::Serialize)
          root_ns_prefix = if root_element.namespace_prefix_explicit && root_element.namespace_prefix
                             root_element.namespace_prefix
                           else
                             root_element.instance_variable_get(:@__xml_namespace_prefix)
                           end
          if root_ns_prefix && !root_ns_prefix.empty?
            instance.instance_variable_set(:@__xml_namespace_prefix,
                                           root_ns_prefix)
          end
          # Track original namespace URI for namespace alias support.
          #
          # When root element's namespace URI differs from the model's canonical URI,
          # it's an alias that should be preserved during serialization.
          root_ns_uri = root_element.namespace_uri
          if root_ns_uri
            model_ns_class = instance.class.mappings_for(:xml)&.namespace_class
            if model_ns_class && model_ns_class.uri != root_ns_uri
              # root_ns_uri differs from canonical - preserve it (alias or other)
              instance.instance_variable_set(:@__xml_original_namespace_uri,
                                             root_ns_uri)
            end
          end

          # Extract namespace declarations from the parsed element tree.
          # This captures ALL xmlns declarations (including unused ones) from the input
          # for round-trip preservation. The own_namespaces on the root element contains
          # all namespaces declared at the root level.
          input_declaration_plan = build_input_declaration_plan(root_element)
          if input_declaration_plan
            instance.xml_declaration_plan = input_declaration_plan
          end
        end
        root_and_parent_assignment(instance, options)
        apply_xml_mapping(data, instance, options)
      end

      # Build a DeclarationPlan from the parsed element tree's namespace declarations.
      #
      # Walks the entire element tree to capture ALL xmlns declarations from input XML,
      # including unused ones (like xmlns:xi for XInclude) and declarations on child elements.
      # The plan preserves WHERE each namespace was declared and its original format/URI.
      #
      # @param root_element [XmlElement] The parsed root element
      # @return [DeclarationPlan, nil] The plan or nil if no namespaces
      def build_input_declaration_plan(root_element)
        return nil unless root_element

        # Walk the element tree collecting namespaces with their declaration locations
        namespaces_with_locations = collect_element_namespaces(root_element)
        return nil if namespaces_with_locations.nil? || namespaces_with_locations.empty?

        # Get the mapping for namespace resolution
        xml_mapping = mappings_for(:xml)

        # Create location-aware DeclarationPlan
        DeclarationPlan.from_input_with_locations(namespaces_with_locations,
                                                  xml_mapping)
      end

      # Recursively collect namespace declarations from all elements in the tree.
      #
      # Each element may declare namespaces via xmlns attributes. The path array tracks
      # the element names from root to current element. Root has path [], its children
      # have path ["childName"], etc. This matches DeclarationPlan.from_input_with_locations
      # expectations where root path is [] and child paths are built by appending.
      #
      # @param element [XmlElement] The element to collect from
      # @param path [Array<String>] Element path from root (empty for root element)
      # @param result [Hash] Accumulated result { path_array => { key => { uri:, prefix:, format: } } }
      # @param visited [Set] Set of visited element object_ids to prevent cycles
      # @return [Hash] { [path_array] => { key => { uri:, prefix:, format: } } }
      def collect_element_namespaces(element, path = [], result = {},
visited = Set.new)
        return result unless element
        return result if visited.include?(element.object_id)

        visited.add(element.object_id)

        # Collect this element's own namespace declarations
        own_ns = element.own_namespaces
        if own_ns&.any?
          input_namespaces = {}
          own_ns.each do |prefix, ns_data|
            key = prefix.nil? ? :default : prefix
            input_namespaces[key] = {
              uri: ns_data.uri,
              prefix: prefix,
              format: prefix.nil? ? :default : :prefix,
            }
          end

          result[path] = input_namespaces unless input_namespaces.empty?
        end

        # Recurse into children with path extended by child local name
        # Use local name (without prefix) since serialization lookup uses
        # xml_element.name which is the local name without namespace prefix
        element.children.each do |child|
          next if child.is_a?(String) # Skip text nodes

          # Strip namespace prefix if present (e.g., "c:childName" -> "childName")
          # to match the key format used during serialization lookup
          full_name = child.name.to_s
          child_local_name = if full_name.include?(":")
                               full_name.split(":",
                                               2).last
                             else
                               full_name
                             end
          child_path = path + [child_local_name]
          collect_element_namespaces(child, child_path, result, visited)
        end

        result
      end

      def model_to_data(model, _format, options = {})
        # Check if model class has a pre-compiled transformation
        model_class = model.class
        if model_class.is_a?(Class) && model_class.include?(::Lutaml::Model::Serialize)
          transformation = model_class.transformation_for(:xml, lutaml_register)

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
        # Use the instance's register if it's a Serializable model
        # This ensures versioned schemas (e.g., MML v2 with lutaml_default_register = :mml_v2)
        # use their native context for mapping resolution, not the parent's context
        effective_register = if instance.is_a?(::Lutaml::Model::Serialize) &&
            instance.respond_to?(:lutaml_register) &&
            instance.lutaml_register
                               instance.lutaml_register
                             else
                               lutaml_register
                             end

        # Performance: Cache frequently accessed options in local variables
        # CRITICAL: Use effective_register to ensure mappings are resolved for the correct register.
        # When options[:register] is non-default, the imported mappings are stored in
        # register-specific storage. Without effective_register, mappings_for(:xml) uses
        # the default register which only has the root element, not the imported child rules.
        # NOTE: Also pass effective_register to .mappings since it defaults to nil register,
        # which would lose the register context and return only class-level rules.
        mappings = options[:mappings] || mappings_for(:xml,
                                                      effective_register).mappings(effective_register)
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

        return instance unless doc

        validate_document!(doc, options)

        set_instance_ordering(instance, doc, ordered_option,
                              mixed_content_option)
        set_schema_location(instance, doc)

        defaults_used = []

        # Performance: Get namespace_uri once if needed for default_namespace
        xml_mapping = mappings_for(:xml)
        namespace_uri = xml_mapping&.namespace_uri

        # Performance: Pre-filter element children once per element instead of
        # scanning all children for each rule (O(children) vs O(children * rules))
        # Note: doc.children can contain Symbols (e.g., namespace declarations), which
        # don't have namespaced_name method, so we filter them out
        element_children = doc.children.reject do |child|
          child.is_a?(String) || child.is_a?(Symbol) ||
            (child.is_a?(::Lutaml::Xml::XmlElement) && child.text?)
        end
        options_with_children = options.merge(_element_children: element_children)

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
                       { default_namespace: rule.namespace,
                         _element_children: element_children }
                     elsif default_namespace.nil? && namespace_uri
                       { default_namespace: namespace_uri,
                         _element_children: element_children }
                     else
                       options_with_children
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
                      attr&.default(effective_register) || rule.to_value_for(instance)
                    else
                      val
                    end
                  end

          from_map = rule.value_map(:from, new_opts)
          value = apply_value_map(value, from_map, attr)
          value = normalize_xml_value(value, rule, attr, new_opts,
                                      effective_register)
          value = rule.transform_value(attr, value, :from, :xml)
          rule.deserialize(instance, value, attributes, context)
        end

        defaults_used.each do |attr_name|
          instance.using_default_for(attr_name)
        end

        run_consolidation(instance, effective_register)

        instance
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
          ns_data = doc.root.namespaces.values.find do |nd|
            nd.uri == namespace_part
          end
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
        # Use the instance's register if it's a Serializable model
        # This ensures versioned schemas (e.g., MML v2 with lutaml_default_register = :mml_v2)
        # use their native context for type resolution, not the parent's context
        effective_register = if instance.is_a?(::Lutaml::Model::Serialize) &&
            instance.respond_to?(:lutaml_register) &&
            instance.lutaml_register
                               instance.lutaml_register
                             else
                               lutaml_register
                             end

        # Performance: Use cached attr from caller if available
        attr = cached_attr || attribute_for_rule(rule)
        attr_type = attr&.type(effective_register)

        # Performance: Cache rule properties accessed in hot loop
        rule_name_str = rule.name.to_s
        rule_namespace_set = rule.namespace_set?
        rule_namespace_param = rule_namespace_set ? rule.instance_variable_get(:@namespace_param) : nil
        rule_prefix_param = rule_namespace_set ? rule.instance_variable_get(:@prefix_param) : nil
        rule_namespace = rule_namespace_set ? rule.namespace : nil
        options[:default_namespace]

        # Enhanced namespace resolution with type support
        rule_names = resolve_rule_names_with_type(rule, attr, options,
                                                  effective_register)

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
                            attr.type_namespace_class(effective_register)
                          end
          type_ns_prefix_str = type_ns_class&.prefix_default&.to_s
        end

        # Performance: Use pre-filtered element children if available via options
        # This avoids O(children * rules) scans by pre-filtering once per element
        # Note: doc.children can contain Symbols (e.g., namespace declarations), which
        # don't have namespaced_name method, so we filter them out
        element_children = options[:_element_children] || doc.children.reject do |child|
          child.is_a?(String) || child.is_a?(Symbol) ||
            (child.is_a?(::Lutaml::Xml::XmlElement) && child.text?)
        end

        # Early exit if no element children - avoid scanning for each rule
        return ::Lutaml::Model::UninitializedClass.instance if element_children.empty?

        children = element_children.select do |child|
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

          # Second: alias-aware matching for nested models
          # When child's namespace URI is an alias of the rule's namespace class,
          # match by local name. This enables parsing XML with alias URIs
          # (e.g., "http://.../") against the canonical namespace class
          # (e.g., "http://.../reqif.xsd").
          child_uri = child.namespace_uri
          if child_uri && type_ns_class && attr_type_is_serializable && type_ns_class.all_uris.include?(child_uri) &&
              child.unprefixed_name == rule_name_str
            next true
          end

          # Third: alias-aware matching for simple types
          # When rule has no explicit namespace but model's namespace class has aliases,
          # match by local name if child's URI is an alias of the model's namespace.
          # This handles cases like <a:item xmlns:a="http://example.com/items/">
          # where the model has namespace with canonical URI "http://example.com/items".
          if child_uri && !rule_namespace_set && !attr_type_is_serializable
            model_mapping = instance.class.mappings_for(:xml)
            model_ns_class = model_mapping&.namespace_class
            if model_ns_class&.all_uris&.include?(child_uri) &&
                child.unprefixed_name == rule_name_str
              next true
            end
          end

          # Fourth: try to match by prefix when child has xmlns="" (explicit blank namespace)
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

        # Performance: Cache rule method check before loop to avoid repeated method calls
        rule_has_custom_method = rule.has_custom_method_for_deserialization?
        if rule_has_custom_method || attr_type == ::Lutaml::Model::Type::Hash
          return_child = attr_type == ::Lutaml::Model::Type::Hash || !attr.collection? if attr
          return return_child ? children.first : children
        end

        return handle_cdata(children) if rule.cdata
        return ::Lutaml::Model::UninitializedClass.instance if children.empty?

        values = attr.build_collection

        instance.value_set_for(attr.name)

        # Performance: Cache values before loop to avoid repeated instance variable access
        instance_is_serializable = instance.is_a?(::Lutaml::Model::Serialize)
        parent_ns_prefix = instance_is_serializable ? instance.instance_variable_get(:@__xml_namespace_prefix) : nil

        # Performance: Cache options except :mappings once before loop
        # This hash is used as a base for each child's cast_options
        # Note: We must create a new hash for each child since attr.cast may modify it
        base_cast_options = options.except(:mappings)
        base_cast_options[:polymorphic] = rule.polymorphic if rule.polymorphic
        base_cast_options[:lutaml_parent] = instance
        base_cast_options[:lutaml_root] = instance.lutaml_root || instance

        children.each do |child|
          if !rule_has_custom_method && attr_type_is_serializable
            # Performance: Build cast_options efficiently
            # Note: Must create new hash each time since attr.cast may modify it
            cast_options = if child.is_a?(::Lutaml::Xml::XmlElement) &&
                (child_namespace_uri = child.namespace_uri)
                             base_cast_options.merge(namespace_uri: child_namespace_uri)
                           else
                             base_cast_options.merge({})
                           end

            cast_result = attr.cast(child, :xml, effective_register,
                                    cast_options)

            # Track original namespace prefix for doubly-defined namespace support.
            # When parsing <a:item> and <b:item> (same URI, different prefixes),
            # we need to preserve which prefix was used for round-trip fidelity.
            # Store on the PARENT model instance keyed by attribute name.
            # Set for ALL attributes (both Serializable and non-Serializable).
            ns_prefix = if child.is_a?(::Lutaml::Xml::XmlElement) &&
                child.namespace_prefix_explicit && child.namespace_prefix
                          child.namespace_prefix
                        end
            if ns_prefix && instance_is_serializable
              prefixes = instance.instance_variable_get(:@__xml_ns_prefixes) || {}
              prefixes[attr.name] = ns_prefix
              instance.instance_variable_set(:@__xml_ns_prefixes, prefixes)
            end

            # Track original alias URI for namespace alias support.
            # When parsing XML with alias URIs (e.g., "http://.../") against a namespace
            # class with canonical URI (e.g., "http://.../reqif.xsd"), store the original
            # alias URI so it can be serialized back correctly.
            child_uri = if child.is_a?(::Lutaml::Xml::XmlElement)
                          child.namespace_uri
                        end
            if child_uri && cast_result.is_a?(::Lutaml::Model::Serialize)
              child_mapping = cast_result.class.mappings_for(:xml)
              child_ns_class = child_mapping&.namespace_class
              if child_ns_class && child_ns_class.uri != child_uri
                # Child's URI differs from canonical - it's an alias
                cast_result.instance_variable_set(
                  :@__xml_original_namespace_uri, child_uri
                )
              end
            end

            # Set @__xml_namespace_prefix on nested Serializable model instances
            # for doubly-defined namespace support.
            #
            # Key distinction between doubly-defined and mixed content:
            # - Doubly-defined: parent's XmlElement uses default format (no explicit prefix).
            #   Parent's @__xml_namespace_prefix is nil. Child should use input prefix.
            # - Mixed content: parent's XmlElement has explicit prefix (e.g., "examplecom:").
            #   Parent's @__xml_namespace_prefix is set. Child should use its own namespace.
            #
            # Check if parent model has @__xml_namespace_prefix set:
            # - Nil/empty: doubly-defined case -> set @__xml_namespace_prefix on child
            # - Set: mixed content case -> don't set (child has its own namespace)
            # Performance: Use cached parent_ns_prefix instead of re-fetching
            if cast_result.is_a?(::Lutaml::Model::Serialize) && ns_prefix && (parent_ns_prefix.nil? || parent_ns_prefix.to_s.empty?)
              cast_result.instance_variable_set(:@__xml_namespace_prefix,
                                                ns_prefix)
            end

            values << cast_result
          elsif attr.raw?
            values << inner_xml_of(child)
          else
            return nil if rule.render_nil_as_nil? && child.nil_element?

            child_text = child.nil_element? ? nil : child&.text
            child_cdata = child&.cdata
            text = if child_text.is_a?(Array) || child_cdata.is_a?(Array)
                     # Mixed content - child elements handle their own text aggregation
                     nil
                   else
                     child_text&.+ child_cdata
                   end
            values << text

            # Track namespace prefix for doubly-defined namespace support.
            # Store on parent model instance keyed by attribute name.
            ns_prefix = if child.is_a?(::Lutaml::Xml::XmlElement) &&
                child.namespace_prefix_explicit && child.namespace_prefix
                          child.namespace_prefix
                        else
                          # Only set ns_prefix for @__xml_ns_prefixes lookup when child's
                          # XmlElement is explicit. For inherited namespaces (child's XmlElement
                          # is nil), leave ns_prefix as-is so @__xml_ns_prefixes is not set.
                          nil
                        end
            if ns_prefix && instance_is_serializable
              # Skip Serializable attribute types (already handled in Serializable branch)
              # attr_type_is_serializable is false here, so attr_type is not Serializable
              prefixes = instance.instance_variable_get(:@__xml_ns_prefixes) || {}
              prefixes[attr.name] = ns_prefix
              instance.instance_variable_set(:@__xml_ns_prefixes, prefixes)
            end
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

      def normalize_xml_value(value, rule, attr, options = {},
effective_register = lutaml_register)
        collection_class = attr&.collection_class || Array
        value = [value].compact if !value.nil? && attr&.collection? && !value.is_a?(collection_class)

        return value unless cast_value?(attr, rule)

        attr.cast(value, :xml, effective_register, options)
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
      # @param effective_register [Symbol] the register to use for type resolution
      # @return [Array<String>] possible namespaced names for matching
      def resolve_rule_names_with_type(rule, attr, options, effective_register)
        # If rule has explicit namespace or no type namespace, use standard logic
        if rule.namespace_set? || !attr
          return rule.namespaced_names(options[:default_namespace])
        end

        # Check if attribute type has namespace
        type_ns_uri = attr.type_namespace_uri(effective_register)

        if type_ns_uri
          # Use type namespace URI for matching (child.namespaced_name uses URI:localname format)
          ["#{type_ns_uri}:#{rule.name}"]
        elsif attr_type_is_serializable(attr, effective_register)
          # For Serializable models, get namespace from the type's XML mappings
          attr_type = attr.type(effective_register)
          attr_type_class = if attr_type.is_a?(Class) && attr_type.include?(::Lutaml::Model::Serialize)
                              attr_type
                            else
                              attr.type_namespace_class(effective_register)
                            end
          if attr_type_class
            attr_type_ns_class = if attr_type_class.respond_to?(:mappings_for)
                                   attr_type_class.mappings_for(:xml)&.namespace_class
                                 end
            if attr_type_ns_class
              return ["#{attr_type_ns_class.uri}:#{rule.name}"]
            end
          end
          # Use existing logic
          rule.namespaced_names(options[:default_namespace])
        else
          # Use existing logic
          rule.namespaced_names(options[:default_namespace])
        end
      end

      def attr_type_is_serializable(attr, effective_register)
        attr_type = attr&.type(effective_register)
        attr_type.is_a?(Class) && attr_type.include?(::Lutaml::Model::Serialize)
      end

      # Run consolidation on any Collection attributes that have organization.
      # This is called as a post-processing step after all mappings are applied.
      #
      # @param instance [Serializable] the deserialized model instance
      # @param register [Symbol] the register id
      def run_consolidation(instance, register)
        return unless instance.is_a?(::Lutaml::Model::Serialize)

        instance.class.attributes.each_value do |attr|
          next unless attr.collection?
          next unless attr.custom_collection?

          collection = instance.public_send(attr.name)
          next unless collection.is_a?(::Lutaml::Model::Collection)
          next unless collection.class.organization

          mappings = collection.class.mappings_for(:xml, register)
          next unless mappings.respond_to?(:consolidation_maps)
          next if mappings.consolidation_maps.empty?

          mappings.consolidation_maps.each do |map|
            org = collection.class.organization
            resolved_map = if map.group_class
                             map
                           else
                             ::Lutaml::Model::ConsolidationMap.new(
                               by: map.by,
                               to: map.to,
                               group_class: org.group_class,
                               rules: map.rules,
                             )
                           end
            ::Lutaml::Model::Consolidation::Engine.run(
              collection, resolved_map, collection.collection
            )
          end
        end
      end
    end
  end
end
