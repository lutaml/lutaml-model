module Lutaml
  module Model
    class XmlTransform < Lutaml::Model::Transform
      def data_to_model(data, _format, options = {})
        instance = model_class.new
        apply_xml_mapping(data, instance, options)
      end

      def model_to_data(model, _format, options = {})
        model
      end

      private

      def apply_xml_mapping(doc, instance, options = {})
        options = Utils.deep_dup(options)
        instance.encoding = options[:encoding]
        return instance unless doc

        if options[:default_namespace].nil?
          options[:default_namespace] = mappings_for(:xml)&.namespace_uri
        end
        mappings = options[:mappings] || mappings_for(:xml).mappings

        raise Lutaml::Model::CollectionTrueMissingError(self, option[:caller_class]) if doc.is_a?(Array)

        doc_order = doc.root.order
        if instance.respond_to?(:ordered=)
          instance.element_order = doc_order
          instance.ordered = mappings_for(:xml).ordered? || options[:ordered]
          instance.mixed = mappings_for(:xml).mixed_content? || options[:mixed_content]
        end

        schema_location = doc.attributes.values.find do |a|
          a.unprefixed_name == "schemaLocation"
        end

        if !schema_location.nil?
          instance.schema_location = Lutaml::Model::SchemaLocation.new(
            schema_location: schema_location.value,
            prefix: schema_location.namespace_prefix,
            namespace: schema_location.namespace,
          )
        end

        defaults_used = []
        validate_sequence!(doc_order)

        mappings.each do |rule|
          raise "Attribute '#{rule.to}' not found in #{context}" unless valid_rule?(rule)

          attr = attribute_for_rule(rule)
          next if attr&.derived?

          value = if rule.raw_mapping?
                    doc.root.inner_xml
                  elsif rule.content_mapping?
                    rule.cdata ? doc.cdata : doc.text
                  elsif val = value_for_rule(doc, rule, options, instance)
                    val
                  elsif rule.render_nil_as_nil?
                    value_for_rule(doc, rule, options, instance)
                  elsif instance.using_default?(rule.to) || rule.render_default
                    defaults_used << rule.to
                    attr&.default || rule.to_value_for(instance)
                  end

          next if rule.render_nil_omit? && (value.nil? || (attr&.collection? && Utils.empty_collection?(value)))

          value = normalize_xml_value(value, rule, attr, options)
          rule.deserialize(instance, value, attributes, context)
        end

        defaults_used.each { |attr_name| instance.using_default_for(attr_name) }

        instance
      end

      def value_for_rule(doc, rule, options, instance)
        rule_names = rule.namespaced_names(options[:default_namespace])

        if rule.attribute?
          doc.root.find_attribute_value(rule_names)
        else
          attr = attribute_for_rule(rule)
          children = doc.children.select do |child|
            rule_names.include?(child.namespaced_name) && !child.text?
          end

          if rule.using_custom_methods? || attr.type == Lutaml::Model::Type::Hash
            return_child = attr.type == Lutaml::Model::Type::Hash || !attr.collection? if attr
            return return_child ? children.first : children
          end

          if Utils.present?(children)
            instance.value_set_for(attr.name)
          end

          if rule.cdata
            values = children.map do |child|
              child.cdata_children&.map(&:text)
            end.flatten
            return children.count > 1 ? values : values.first
          end

          values = children.map do |child|
            if !rule.using_custom_methods? && attr.type <= Serialize
              cast_options = options.except(:mappings)
              cast_options[:polymorphic] = rule.polymorphic if rule.polymorphic

              attr.cast(child, :xml, cast_options)
            elsif attr.raw?
              inner_xml_of(child)
            else
              return nil if rule.render_nil_as_nil? && child.nil_element?
              return [] if rule.render_empty_as_nil? && child.nil_element?

              text = child&.children&.first&.text
              if (rule.render_nil_as_blank? || rule.render_empty_as_blank?) && text.nil? && attr.collection?
                return []
              else
                text
              end
            end
          end
          attr&.collection? ? values : values.first
        end
      end

      def normalize_xml_value(value, rule, attr, options = {})
        value = [value].compact if attr&.collection? && !value.is_a?(Array) && !value.nil?

        return value unless cast_value?(attr, rule)

        options.merge(caller_class: self, mixed_content: rule.mixed_content)
        attr.cast(
          value,
          :xml,
          options,
        )
      end

      def cast_value?(attr, rule)
        attr &&
          !rule.raw_mapping? &&
          !rule.content_mapping? &&
          !rule.custom_methods[:from]
      end

      def text_hash?(attr, value)
        return false unless value.is_a?(Hash)
        return value.one? && value.text? unless attr

        !(attr.type <= Serialize) && attr.type != Lutaml::Model::Type::Hash
      end

      def ensure_utf8(value)
        case value
        when String
          value.encode("UTF-8", invalid: :replace, undef: :replace,
                                replace: "")
        when Array
          value.map { |v| ensure_utf8(v) }
        when Hash
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
        when XmlAdapter::XmlElement
          node.inner_xml
        else
          node.children.map(&:to_xml).join
        end
      end

      def validate_sequence!(element_order)
        mapping_sequence = mappings_for(:xml).element_sequence
        current_order = element_order.filter_map(&:element_tag)

        mapping_sequence.each do |mapping|
          mapping.validate_content!(current_order)
        end
      end
    end
  end
end
