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
      def model_to_data(model, _format, _options = {})
        model
      end

      private

      def apply_xml_mapping(doc, instance, options = {})
        options = prepare_options(options)
        instance.encoding = options[:encoding]
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
          if rule.namespace_set?
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

        instance.schema_location = Lutaml::Model::SchemaLocation.new(
          schema_location: schema_location.value,
          prefix: schema_location.namespace_prefix,
          namespace: schema_location.namespace,
        )
      end

      def value_for_xml_attribute(doc, rule, rule_names)
        value = doc.root.find_attribute_value(rule_names)

        value = value&.split(rule.delimiter) if rule.delimiter

        value = rule.as_list[:import].call(value) if rule.as_list && rule.as_list[:import]

        value
      end

      def value_for_rule(doc, rule, options, instance)
        rule_names = rule.namespaced_names(options[:default_namespace])
        return value_for_xml_attribute(doc, rule, rule_names) if rule.attribute?

        attr = attribute_for_rule(rule)
        attr_type = attr&.type(__register)

        children = doc.children.select do |child|
          next false if child.text?

          # First try exact namespace match
          next true if rule_names.include?(child.namespaced_name)

          # Fallback: if the child has a different namespace and attr_type is Serializable,
          # match by unprefixed name (child declares its own namespace)
          if attr_type && attr_type <= Serialize
            rule_names.any? { |rn| rn.split(":").last == child.unprefixed_name }
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
    end
  end
end
