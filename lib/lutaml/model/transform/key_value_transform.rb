module Lutaml
  module Model
    class KeyValueTransform < Lutaml::Model::Transform
      def data_to_model(data, format, options = {})
        instance = model_class.new
        mappings = extract_mappings(options, format)

        mappings.each do |rule|
          process_mapping_rule(data, instance, format, rule)
        end

        instance
      end

      def model_to_data(instance, format, options = {})
        only = options[:only]
        except = options[:except]
        mappings = mappings_for(format).mappings

        mappings.each_with_object({}) do |rule, hash|
          name = rule.to
          next if except&.include?(name) || (only && !only.include?(name))

          attribute = attributes[name]

          next handle_delegate(instance, rule, hash, format) if rule.delegate

          if rule.custom_methods[:to]
            next instance.send(rule.custom_methods[:to], instance, hash)
          end

          value = instance.send(name)

          if rule.raw_mapping?
            adapter = Lutaml::Model::FormatRegistry.send(:"#{format}_adapter")
            return adapter.parse(value, options)
          end

          if export_method = rule.transform[:export] || attribute.transform_export_method
            value = export_method.call(value)
          end

          next hash.merge!(generate_hash_from_child_mappings(attribute, value, format, rule.root_mappings)) if rule.root_mapping?

          value = if rule.child_mappings
                    generate_hash_from_child_mappings(attribute, value, format, rule.child_mappings)
                  else
                    attribute.serialize(value, format, options)
                  end

          next unless rule.render?(value, instance) || attribute&.initialize_empty?

          value = [] if rule.render_nil_as_empty? && value.nil?

          rule_from_name = rule.multiple_mappings? ? rule.from.first.to_s : rule.from.to_s
          hash[rule_from_name] = value
        end
      end

      private

      def generate_hash_from_child_mappings(attr, value, format, child_mappings)
        return value unless child_mappings

        hash = {}

        if child_mappings.values == [:key]
          klass = value.first.class
          mappings = klass.mappings_for(format)

          klass.attributes.each_key do |name|
            next if child_mappings.key?(name.to_sym) || child_mappings.key?(name.to_s)

            child_mappings[name.to_sym] = mappings.find_by_to(name)&.name.to_s || name.to_s
          end
        end

        value.each do |child_obj|
          map_key = nil
          map_value = {}
          mapping_rules = attr.type.mappings_for(format)

          child_mappings.each do |attr_name, path|
            mapping_rule = mapping_rules.find_by_to(attr_name)

            attr_value = child_obj.send(attr_name)

            attr_value = if attr_value.is_a?(Lutaml::Model::Serialize)
                           attr_value.to_yaml_hash
                         elsif attr_value.is_a?(Array) && attr_value.first.is_a?(Lutaml::Model::Serialize)
                           attr_value.map(&:to_yaml_hash)
                         else
                           attr_value
                         end

            next unless mapping_rule&.render?(attr_value, nil)

            if path == :key
              map_key = attr_value
            elsif path == :value
              map_value = attr_value
            else
              path = [path] unless path.is_a?(Array)
              path[0...-1].inject(map_value) do |acc, k|
                acc[k.to_s] ||= {}
              end.public_send(:[]=, path.last.to_s, attr_value)
            end
          end

          map_value = nil if map_value.empty?
          hash[map_key] = map_value
        end

        hash
      end

      def handle_delegate(instance, rule, hash, format)
        name = rule.to
        value = instance.send(rule.delegate).send(name)
        return if value.nil? && !rule.render_nil

        attribute = instance.send(rule.delegate).class.attributes[name]
        rule_from_name = rule.multiple_mappings? ? rule.from.first.to_s : rule.from.to_s
        hash[rule_from_name] = attribute.serialize(value, format)
      end

      def extract_mappings(options, format)
        options[:mappings] || mappings_for(format).mappings
      end

      def process_mapping_rule(doc, instance, format, rule)
        raise "Attribute '#{rule.to}' not found in #{self}" unless valid_rule?(rule)

        attr = attribute_for_rule(rule)
        return if attr&.derived?

        value = extract_rule_value(doc, rule, format, attr)

        return if rule.render_nil_omit? && value.nil?

        value = [] if rule.render_nil_as_empty? && value.nil?
        value = [] if (rule.render_empty_as_nil? && value.nil?) || (rule.render_empty_as_empty? && Utils.empty_collection?(value))

        return process_custom_method(rule, instance, value) if rule.using_custom_methods?

        value = translate_mappings(value, rule.hash_mappings, attr, format)
        value = cast_value(value, attr, format, rule) unless rule.hash_mappings

        attr.valid_collection!(value, context)
        rule.deserialize(instance, value, attributes, self)
      end

      def extract_rule_value(doc, rule, format, attr)
        rule_names = rule.multiple_mappings? ? rule.name : [rule.name]

        rule_names.each do |rule_name|
          return doc if rule.root_mapping?
          return convert_to_format(doc, format) if rule.raw_mapping?
          return doc[rule_name.to_s] if doc.key?(rule_name.to_s)
          return doc[rule_name.to_sym] if doc.key?(rule_name.to_sym)
        end

        attr&.default
      end

      def convert_to_format(doc, format)
        adapter = Lutaml::Model::FormatRegistry.public_send(:"#{format}_adapter")
        adapter.new(doc).public_send(:"to_#{format}")
      end

      def process_custom_method(rule, instance, value)
        return unless Utils.present?(value)

        model_class.new.send(rule.custom_methods[:from], instance, value)
      end

      def cast_value(value, attr, format, rule)
        cast_options = rule.polymorphic ? { polymorphic: rule.polymorphic } : {}
        attr.cast(value, format, cast_options)
      end

      def translate_mappings(hash, child_mappings, attr, format)
        return hash unless child_mappings

        hash.map do |key, value|
          process_child_mapping(key, value, child_mappings, attr, format, hash)
        end
      end

      def process_child_mapping(key, value, child_mappings, attr, format, hash)
        child_hash = build_child_hash(key, value, child_mappings, attr, format)

        if only_keys_mapped?(child_mappings, hash)
          child_hash.merge!(value)
        end

        map_child_data(child_hash, attr, format)
      end

      def build_child_hash(key, value, child_mappings, attr, format)
        child_mappings.to_h do |attr_name, path|
          attr_value = extract_attr_value(path, key, value)
          attr_rule = attr.type.mappings_for(format).find_by_to(attr_name)
          [attr_rule.from.to_s, attr_value]
        end
      end

      def extract_attr_value(path, key, value)
        case path
        when :key then key
        when :value then value
        else
          path = Array(path)
          value.dig(*path.map(&:to_s))
        end
      end

      def only_keys_mapped?(child_mappings, hash)
        child_mappings.values == [:key] && hash.values.all?(Hash)
      end

      def map_child_data(child_hash, attr, format)
        self.class.data_to_model(
          attr.type,
          child_hash,
          format,
          { mappings: attr.type.mappings_for(format).mappings },
        )
      end
    end
  end
end
