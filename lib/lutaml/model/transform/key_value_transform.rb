module Lutaml
  module Model
    class KeyValueTransform < Lutaml::Model::Transform
      def data_to_model(data, format, options = {})
        instance = if model_class.include?(Lutaml::Model::Serialize)
                     model_class.new({}, register: register)
                   else
                     model_class.new(register)
                   end
        mappings = extract_mappings(options, format)

        Utils.add_if_present(options, :key_mappings, mappings.key_mappings)
        Utils.add_if_present(options, :value_mappings, mappings.value_mappings)

        mappings.mappings.each do |rule|
          process_mapping_rule(data, instance, format, rule, options)
        end

        instance
      end

      def model_to_data(instance, format, options = {})
        mappings = mappings_for(format)

        hash = {}
        mappings.mappings.each do |rule|
          next unless valid_mapping?(rule, options)
          next handle_delegate(instance, rule, hash, format) if rule.delegate

          value = process_mapping_for_instance(instance, hash, format, rule, options)
          if mappings.key_value_mappings? && value
            hash[rule_from_name(rule)] = handle_key_value_mappings(value, mappings)
          end
        end

        hash
      end

      private

      def process_mapping_for_instance(instance, hash, format, rule, options)
        if rule.custom_methods[:to]
          return instance.send(rule.custom_methods[:to], instance, hash)
        end

        attribute = attributes[rule.to]
        value = rule.serialize(instance)

        return handle_raw_mapping(hash, value, format, options) if rule.raw_mapping?
        return handle_root_mappings(hash, value, format, rule, attribute) if rule.root_mapping?

        value = ExportTransformer.call(value, rule, attribute)

        value = serialize_value(value, rule, attribute, format, options)

        return unless rule.render?(value, instance)

        value = apply_value_map(value, rule.value_map(:to, options), attribute)

        hash[rule_from_name(rule)] = value
      end

      def valid_mapping?(rule, options)
        only = options[:only]
        except = options[:except]
        name = rule.to

        (except.nil? || !except.include?(name)) &&
          (only.nil? || only.include?(name))
      end

      def handle_raw_mapping(hash, value, format, options)
        result = Lutaml::Model::Config.adapter_for(format).parse(value, options)

        hash.merge!(result)
      end

      def handle_root_mappings(hash, value, format, rule, attr)
        hash.merge!(
          generate_hash_from_child_mappings(
            attr,
            value,
            format,
            rule.root_mappings,
          ),
        )
      end

      def serialize_value(value, rule, attr, format, options)
        return attr.serialize(value, format, register, options) unless rule.child_mappings

        generate_hash_from_child_mappings(
          attr, value, format, rule.child_mappings
        )
      end

      def rule_from_name(rule)
        rule.multiple_mappings? ? rule.from.first.to_s : rule.from.to_s
      end

      def generate_hash_from_child_mappings(attr, value, format, child_mappings)
        return value unless child_mappings

        hash = {}

        generate_remaining_mappings_for_value(child_mappings, value, format)

        value.each do |child_obj|
          rules = attr.type(register).mappings_for(format)

          hash.merge!(
            extract_hash_for_child_mapping(child_mappings, child_obj, rules),
          )
        end

        hash
      end

      # Generates remaining child mappings for all attributes when only
      # the :key mapping (e.g., { name: :key }) is provided.
      # If any additional mappings (e.g., { name: :key, id: :identifier })
      # are specified, no additional child mappings will be generated.
      def generate_remaining_mappings_for_value(child_mappings, value, format)
        return if child_mappings.values != [:key]

        klass = value.first.class
        mappings = klass.mappings_for(format)

        klass.attributes.each_key do |name|
          next if Utils.string_or_symbol_key?(child_mappings, name)

          child_mappings[name.to_sym] = child_mapping_for(name, mappings)
        end
      end

      def child_mapping_for(name, mappings)
        mappings.find_by_to(name)&.name.to_s || name.to_s
      end

      def extract_hash_for_child_mapping(child_mappings, child_obj, rules)
        key = nil
        value = {}

        child_mappings.each do |attr_name, path|
          rule = rules.find_by_to(attr_name)

          attr_value = normalize_attribute_value(child_obj.send(attr_name))

          next unless rule&.render?(attr_value, nil)
          next key = attr_value if path == :key

          value = extract_hash_value_for_child_mapping(path, attr_value, value)
        end

        value = nil if value.empty?
        { key => value }
      end

      def normalize_attribute_value(value)
        if value.is_a?(Lutaml::Model::Serialize)
          value.to_hash
        elsif value.is_a?(Array) && value.first.is_a?(Lutaml::Model::Serialize)
          value.map(&:to_hash)
        else
          value
        end
      end

      def extract_hash_value_for_child_mapping(path, value, map_value)
        return value if path == :value

        path = [path] unless path.is_a?(Array)
        path[0...-1].inject(map_value) do |acc, k|
          acc[k.to_s] ||= {}
        end.public_send(:[]=, path.last.to_s, value)

        map_value
      end

      def handle_delegate(instance, rule, hash, format)
        value = extract_value_for_delegate(instance, rule)
        return if value.nil? && !rule.render_nil

        attribute = instance.send(rule.delegate).class.attributes[rule.to]
        hash[rule_from_name(rule)] = attribute.serialize(value, format, register)
      end

      def extract_value_for_delegate(instance, rule)
        instance.send(rule.delegate).send(rule.to)
      end

      def extract_mappings(options, format)
        options[:mappings] || mappings_for(format)
      end

      def process_mapping_rule(doc, instance, format, rule, options = {})
        raise "Attribute '#{rule.to}' not found in #{self}" unless valid_rule?(rule)

        attr = attribute_for_rule(rule)
        return if attr&.derived?

        value = extract_rule_value(doc, rule, format, attr, options)
        value = apply_value_map(value, rule.value_map(:from, options), attr)

        return process_custom_method(rule, instance, value) if rule.has_custom_method_for_deserialization?

        value = translate_mappings(value, rule.hash_mappings, attr, format)
        value = cast_value(value, attr, format, rule) unless rule.hash_mappings

        attr.valid_collection!(value, context)
        rule.deserialize(instance, value, attributes, self)
      end

      def extract_rule_value(doc, rule, format, attr, options = {})
        rule_names = rule.multiple_mappings? ? rule.name : [rule.name]

        rule_names.each do |rule_name|
          value = rule_value_for(rule_name, doc, rule, format, attr, options)
          value = transform_mapped_value(value, options) if should_transform_value?(value, options)
          return value if Utils.initialized?(value)
        end

        Lutaml::Model::UninitializedClass.instance
      end

      def should_transform_value?(value, options)
        (options[:key_mappings] || options[:value_mappings]) &&
          value.is_a?(Hash)
      end

      def transform_mapped_value(value, options)
        value.map do |k, v|
          if v.is_a?(Hash)
            transform_hash_value(v, k, options)
          else
            transform_simple_value(k, v, options)
          end
        end
      end

      def transform_hash_value(hash_value, key, options)
        hash_value.merge(
          {
            options[:key_mappings].to_instance.to_s => key,
          },
        )
      end

      def transform_simple_value(key, value, options)
        {
          options[:key_mappings].to_instance.to_s => key,
          options[:value_mappings].as_attribute.to_s => value,
        }
      end

      def rule_value_for(name, doc, rule, format, attr, _options = {})
        if rule.root_mapping?
          doc
        elsif rule.raw_mapping?
          convert_to_format(doc, format)
        elsif Utils.string_or_symbol_key?(doc, name)
          Utils.fetch_with_string_or_symbol_key(doc, name)
        elsif attr&.default_set?(register)
          attr.default(register)
        else
          Lutaml::Model::UninitializedClass.instance
        end
      end

      def convert_to_format(doc, format)
        adapter = Lutaml::Model::Config.adapter_for(format)
        adapter.new(doc).public_send(:"to_#{format}")
      end

      def process_custom_method(rule, instance, value)
        return unless Utils.present?(value)

        model_class.new.send(rule.custom_methods[:from], instance, value)
      end

      def cast_value(value, attr, format, rule)
        cast_options = rule.polymorphic ? { polymorphic: rule.polymorphic } : {}
        attr.cast(value, format, register, cast_options)
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
          attr_rule = attr.type(register).mappings_for(format).find_by_to(attr_name)
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
          attr.type(register),
          child_hash,
          format,
          { mappings: attr.type(register).mappings_for(format) },
        )
      end

      def handle_key_value_mappings(value, mappings)
        value.to_h do |v|
          [
            v[mappings.key_mappings.to_instance.to_s],
            if mappings.value_mappings
              v[mappings.value_mappings.as_attribute.to_s]
            else
              v.except(mappings.key_mappings.to_instance.to_s)
            end,
          ]
        end
      end
    end
  end
end
