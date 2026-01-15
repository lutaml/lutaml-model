module Lutaml
  module Model
    class XmlTransform < Lutaml::Model::Transform
      def data_to_model(data, _format, options = {})
        if model_class.include?(Lutaml::Model::Serialize)
          instance = model_class.new({ __register: __register })
        else
          instance = model_class.new
          register_accessor_methods_for(instance, __register)
        end
        root_and_parent_assignment(instance, options)
        apply_xml_mapping(data, instance, options)
      end

      # TODO: this should be extracted from adapters and moved here to be reused
      def model_to_data(model, _format, options = {})
        # Check if model class has a pre-compiled transformation
        if model.class.respond_to?(:transformation_for)
          transformation = model.class.transformation_for(:xml, __register)

          # If transformation exists and is an XmlTransformation, use it
          if transformation.is_a?(Lutaml::Model::Xml::Transformation)
            return transformation.transform(model, options)
          end
        end

        # Fallback to returning model for legacy path
        model
      end

      private

      def apply_xml_mapping(doc, instance, options = {})
        options = prepare_options(options)
        instance.encoding = options[:encoding]
        instance.doctype = options[:doctype] if options[:doctype]

        # Transfer XML declaration info if present (Issue #1)
        if doc.respond_to?(:xml_declaration) && doc.xml_declaration
          instance.instance_variable_set(:@xml_declaration, doc.xml_declaration)
        end

        # Transfer input namespaces if present (Issue #3: Namespace Preservation)
        if doc.respond_to?(:input_namespaces) && doc.input_namespaces&.any?
          instance.instance_variable_set(:@__input_namespaces, doc.input_namespaces)
        end

        return instance unless doc

        mappings = options[:mappings] || mappings_for(:xml).mappings

        validate_document!(doc, options)

        set_instance_ordering(instance, doc, options)
        set_schema_location(instance, doc)

        defaults_used = []

        mappings.each do |rule|
          attr = attribute_for_rule(rule)
          next if attr&.derived?

          raise "Attribute '#{rule.to}' not found in #{context}" unless valid_rule?(
            rule, attr
          )

          new_opts = options.dup
          # Don't overwrite default_namespace for :inherit - it needs the parent's namespace
          if rule.namespace_set? && rule.instance_variable_get(:@namespace_param) != :inherit
            new_opts[:default_namespace] = rule.namespace
          end

          value = if rule.raw_mapping?
                    doc.root.inner_xml
                  elsif rule.content_mapping?
                    rule.cdata ? doc.cdata : doc.text
                  else
                    val = value_for_rule(doc, rule, new_opts, instance)

                    if (val.nil? || Utils.uninitialized?(val)) &&
                        (instance.using_default?(rule.to) || rule.render_default)
                      defaults_used << rule.to
                      attr&.default(__register) || rule.to_value_for(instance)
                    else
                      val
                    end
                  end

          value = apply_value_map(value, rule.value_map(:from, new_opts), attr)
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
        if model_class.respond_to?(:mappings_for)
          mapping = model_class.mappings_for(:xml, __register)
          # Check if doc responds to input_namespaces (handles nested elements that are OxElement)
          if mapping && doc.respond_to?(:input_namespaces) && doc.input_namespaces&.any?
            # Create plan from input namespaces (format preservation)
            plan = Lutaml::Model::Xml::DeclarationPlan.from_input(
              doc.input_namespaces,
              mapping
            )

            # Store plan in instance for use during serialization
            if instance.respond_to?(:__input_declaration_plan=)
              instance.__input_declaration_plan = plan
            end
          end
        end

        instance
      end

      def prepare_options(options)
        opts = Utils.deep_dup(options)
        opts[:default_namespace] ||= mappings_for(:xml)&.namespace_uri

        opts
      end

      def validate_document!(doc, options)
        return unless doc.is_a?(Array)

        raise Lutaml::Model::CollectionTrueMissingError(
          context,
          options[:caller_class],
        )
      end

      def set_instance_ordering(instance, doc, options)
        return unless instance.respond_to?(:ordered=)

        instance.element_order = doc.root.order
        instance.ordered = mappings_for(:xml).ordered? || options[:ordered]
        instance.mixed = mappings_for(:xml).mixed_content? || options[:mixed_content]
      end

      def set_schema_location(instance, doc)
        schema_location = doc.attributes.values.find do |a|
          a.unprefixed_name == "schemaLocation"
        end

        return if schema_location.nil?

        # Store raw schemaLocation string as metadata
        # SchemaLocation class is for programmatic creation with XmlNamespace classes only
        # When parsing XML, we just preserve the string value as-is
        instance.instance_variable_set(:@raw_schema_location, schema_location.value)
      end

      def value_for_xml_attribute(doc, rule, rule_names)
        # For attributes, rule_names may contain URI:name format, but find_attribute_value
        # expects prefix:name or just name, so we need to convert URI to prefix
        attribute_names = rule_names.filter_map do |rn|
          if rn.include?("://")
            # This is a URI:name format, need to find the actual prefix used in the document
            # CRITICAL: Split on LAST colon to handle URIs with colons (http://...)
            # "http://www.w3.org/XML/1998/namespace:lang" should split into:
            #   uri = "http://www.w3.org/XML/1998/namespace"
            #   local_name = "lang"
            last_colon_index = rn.rindex(":")
            uri = rn[0...last_colon_index]
            local_name = rn[(last_colon_index + 1)..-1]

            # Get all matching attributes by URI and local name
            doc.root.attributes.values.find do |attr|
              attr.namespace == uri && attr.unprefixed_name == local_name
            end&.name || rn
          else
            rn
          end
        end

        value = doc.root.find_attribute_value(attribute_names)

        value = value&.split(rule.delimiter) if rule.delimiter

        value = rule.as_list[:import].call(value) if rule.as_list && rule.as_list[:import]

        value
      end

      def value_for_rule(doc, rule, options, instance)
        attr = attribute_for_rule(rule)

        # Enhanced namespace resolution with type support
        rule_names = resolve_rule_names_with_type(rule, attr, options)

        return value_for_xml_attribute(doc, rule, rule_names) if rule.attribute?

        attr_type = attr&.type(__register)

        children = doc.children.select do |child|
          next false if child.is_a?(String)

          # Handle XmlElement children with text? method
          next false if child.respond_to?(:text?) && child.text?

          # Handle explicit namespace: nil with prefix: nil
          # When both namespace: nil and prefix: nil are set, this means "no namespace constraint"
          # The child element can declare its own namespace and should still match by local name
          if rule.namespace_set? && rule.namespace.nil? &&
             rule.instance_variable_get(:@namespace_param).nil? &&
             rule.instance_variable_get(:@prefix_param).nil?
            # Match by unprefixed name only, regardless of child's namespace
            next child.unprefixed_name == rule.name.to_s
          end

          # First try exact namespace match
          next true if rule_names.include?(child.namespaced_name)

          # Second: try to match by prefix when child has xmlns="" (explicit blank namespace)
          # This handles the case where elements have prefixed names but are in blank namespace
          # e.g., <GML:ApplicationSchema xmlns=""> should match the rule expecting GML namespace
          if child.namespace_prefix && attr_type && attr_type <= Serialize
            # Get the type namespace class from the attribute
            type_ns_class = attr.type_namespace_class(__register)
            if type_ns_class && child.namespace_prefix == type_ns_class.prefix_default.to_s
              next true
            end
          end

          # Fallback: if the child has a different namespace and attr_type is Serializable,
          # match by unprefixed name (child declares its own namespace)
          #
          # CRITICAL: Only use fallback for unqualified children (no prefix).
          # Children with explicit prefixes should NOT match via fallback, even if xmlns="" is set.
          # This ensures that GML:ApplicationSchema doesn't match CityGML:ApplicationSchema just because
          # they have the same unprefixed name.
          if attr_type && attr_type <= Serialize
            # Only match by unprefixed name if child doesn't have an explicit namespace prefix
            # This prevents cross-namespace matching when elements have the same local name
            !child.namespace_prefix && rule_names.any? { |rn| rn.split(":").last == child.unprefixed_name }
          else
            false
          end
        end

        if rule.has_custom_method_for_deserialization? || attr_type == Lutaml::Model::Type::Hash
          return_child = attr_type == Lutaml::Model::Type::Hash || !attr.collection? if attr
          return return_child ? children.first : children
        end

        return handle_cdata(children) if rule.cdata
        return Lutaml::Model::UninitializedClass.instance if children.empty?

        values = attr.build_collection

        instance.value_set_for(attr.name)

        children.each do |child|
          if !rule.has_custom_method_for_deserialization? && attr_type <= Serialize
            cast_options = options.except(:mappings)
            cast_options[:polymorphic] = rule.polymorphic if rule.polymorphic
            cast_options[:register] = __register
            cast_options[:__parent] = instance
            cast_options[:__root] = instance.__root || instance

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
        when Xml::XmlElement
          node.inner_xml
        else
          node.children.map(&:to_xml).join
        end
      end

      # Resolve rule names with type namespace support
      #
      # @param rule [Xml::MappingRule] the mapping rule
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
