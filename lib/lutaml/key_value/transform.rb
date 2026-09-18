module Lutaml
  module KeyValue
    class Transform < Lutaml::Model::Transform
      def data_to_model(data, format, options = {})
        # Use child's own default register if it has one
        # This ensures versioned schemas (e.g., MML v2 with lutaml_default_register = :mml_v2)
        # are instantiated with their native context
        child_register = Lutaml::Model::Register.resolve_for_child(
          model_class, lutaml_register
        )

        if model_class.include?(Lutaml::Model::Serialize)
          instance = model_class.new(lutaml_register: child_register)
        else
          instance = model_class.new
          register_accessor_methods_for(instance, child_register)
        end
        root_and_parent_assignment(instance, options)
        mappings = extract_mappings(options, format)

        mappings.mappings(lutaml_register).each do |rule|
          process_mapping_rule(data, instance, format, rule, options)
        end

        instance
      end

      def model_to_data(instance, format, options = {})
        # NEW ARCHITECTURE: Use KeyValue::Transformation if available
        # This provides symmetric OOP architecture with XmlDataModel
        if context.is_a?(Class) && context.include?(Lutaml::Model::Serialize)
          transformation = context.transformation_for(format, lutaml_register)

          # transformation_for returns nil for cyclic dependencies or :building sentinel
          # Fall back to legacy approach in these cases
          if transformation.is_a?(Lutaml::KeyValue::Transformation)
            # Use new Transformation to get KeyValueElement
            kv_element = transformation.transform(instance, options)
            # Convert KeyValueElement to hash for backward compatibility with adapters
            # The to_hash method returns {"__root__" => {actual_hash}}
            kv_hash = kv_element.to_hash
            # For root element, return just the content hash
            return kv_hash["__root__"] || kv_hash
          end
        end

        # LEGACY ARCHITECTURE: Fall back to Hash-based approach
        # This maintains backward compatibility for models without transformations
        mappings = extract_mappings(options, format)

        hash = {}
        mappings.mappings(lutaml_register).each do |rule|
          next unless valid_mapping?(rule, options)

          process_rule!(instance, rule, hash, format, mappings, options)
        end

        hash.keys == [""] ? hash[""] : hash
      end

      private

      def process_rule!(instance, rule, hash, format, _mappings, options)
        return handle_delegate(instance, rule, hash, format) if rule.delegate

        process_mapping_for_instance(instance, hash, format, rule, options)
      end

      def process_mapping_for_instance(instance, hash, format, rule, options)
        if rule.custom_methods[:to]
          to_method = rule.custom_methods[:to]
          # lutaml-model#550: custom methods may declare a third context
          # parameter to receive the options passed to `to_*`.
          if instance.method(to_method).parameters.size >= 3
            return instance.public_send(to_method, instance, hash,
                                        options[:context])
          end

          return instance.public_send(to_method, instance, hash)
        end

        attribute = attributes[rule.to]

        # TODO.max-perf/10: plain scalar/collection rules take a fast
        # lane — memoized wire name, shared render? semantics, one
        # serialize dispatch — collapsing the interpretive branch
        # probes below. Rules with any special feature stay on the
        # full path.
        if (plan = kv_serialize_plan(rule, attribute, instance))
          value = instance.public_send(attribute.name)
          if rule.render?(value, instance)
            hash[plan.wire] = attribute.serialize(value, format,
                                                  lutaml_register, options)
          end
          return
        end

        value = rule.serialize(instance)

        if rule.can_transform_to?(attribute, format)
          hash[rule_from_name(rule)] =
            rule.transform_value(attribute, value, :to, format)
          return
        end

        if rule.raw_mapping?
          return handle_raw_mapping(hash, value, format,
                                    options)
        end
        if rule.root_mapping?
          return handle_root_mappings(hash, value, format, rule,
                                      attribute)
        end

        # Use the format parameter passed in instead of hardcoding to :json
        value = ExportTransformer.call(value, rule, attribute,
                                       format: format,
                                       context: options[:context])

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
        unless rule.child_mappings
          return attr.serialize(value, format, lutaml_register,
                                options)
        end

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

        attr_type = attr.type(lutaml_register)
        value.each do |child_obj|
          rules = attr_type.mappings_for(format)

          hash.merge!(
            extract_hash_for_child_mapping(child_mappings, child_obj, rules,
                                           format),
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
        mappings = klass.mappings_for(format, lutaml_register)

        klass.attributes(lutaml_register).each_key do |name|
          next if Utils.string_or_symbol_key?(child_mappings, name)

          child_mappings[name.to_sym] = child_mapping_for(name, mappings)
        end
      end

      def child_mapping_for(name, mappings)
        mappings.find_by_to(name)&.name.to_s
      end

      def extract_hash_for_child_mapping(child_mappings, child_obj, rules,
format)
        key = nil
        value = {}

        child_mappings.each do |attr_name, path|
          rule = rules.find_by_to!(attr_name)
          attr_value = normalize_attribute_value(child_obj, rule.from, format)

          next unless rule&.render?(attr_value, nil)
          next key = attr_value if path == :key

          value = extract_hash_value_for_child_mapping(path, attr_value, value)
        end

        value = nil if value.empty?
        { key => value }
      end

      def normalize_attribute_value(value, attr_name, format)
        Lutaml::Model::Config.adapter_for(format).parse(
          value.public_send(:"to_#{format}"),
        )[attr_name.to_s]
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
        return if value.nil? && rule.value_map(:to)[:nil] == :omitted

        attribute = instance.public_send(rule.delegate).class.attributes(lutaml_register)[rule.to]
        hash[rule_from_name(rule)] =
          attribute.serialize(value, format, lutaml_register)
      end

      def extract_value_for_delegate(instance, rule)
        instance.public_send(rule.delegate).public_send(rule.to)
      end

      def extract_mappings(options, format)
        options[:mappings] || mappings_for(format, lutaml_register)
      end

      def process_mapping_rule(doc, instance, format, rule, options = {})
        attr = attribute_for_rule(rule)
        return if attr&.derived?

        raise "Attribute '#{rule.to}' not found in #{self}" unless valid_rule?(
          rule, attr
        )

        if (plan = kv_rule_plan(format, rule, attr)) &&
            (value = kv_fast_extract(doc, plan))
          rule.deserialize(instance, kv_fast_cast(value, plan, instance),
                           attributes, self, options[:context])
          return
        end

        value = rule_value_extractor_class.call(rule, doc, format, attr,
                                                lutaml_register, options, instance)
        value = apply_value_map(value, rule.value_map(:from, options), attr)

        if rule.has_custom_method_for_deserialization?
          # An empty value ("", [], {}) is a present value per the
          # missing-values semantics and must reach the custom method;
          # only nil (non-existent) skips it (lutaml-model#746).
          return if value.nil?

          warn "PROBE-264 keys=#{options.keys.inspect} ctx=#{options[:context].inspect}"
          return rule.deserialize(instance, value, attributes, model_class,
                                  options[:context])
        end

        value = rule.transform_value(attr, value, :from, format)
        value = translate_mappings(value, rule.hash_mappings, attr, format,
                                   instance)
        unless rule.hash_mappings
          value = cast_value(value, attr, format, rule,
                             instance)
        end

        # Range errors stay eager here. The over-count error only fires when the
        # attribute is not a collection, so this guard defers exactly that case
        # to `.validate` while leaving declared ranges checked at parse. A mapped
        # PORO has no `.validate` to defer into, so it keeps the eager check.
        if attr.collection? || !instance.is_a?(Lutaml::Model::Serialize)
          attr.valid_collection!(value, context)
        end
        rule.deserialize(instance, value, attributes, self,
                         options[:context])
      end

      # Compiled rule plans (TODO.perf/07): for plain scalar rules the
      # per-value interpretation (extraction dispatch, type resolution,
      # per-element probes, validation inside casts) collapses to a
      # precomputed wire name, target class, and identity-guard cast.
      # Guard + cached target — an inline cache per rule. Complex rules
      # (custom methods, transforms, value maps, delegates, hash mappings,
      # unions, polymorphism) return nil and keep the interpretive path.
      KvRulePlan = ::Struct.new(:wire, :klass, :collection)

      # Memoized (per transform) wire name for plain rules — the from
      # spelling never changes after definition.
      KvSerializePlan = ::Struct.new(:wire)

      def kv_serialize_plan(rule, attr, _instance)
        return nil if rule.delegate || rule.raw_mapping? || rule.root_mapping? ||
          rule.hash_mappings || rule.child_mappings ||
          rule.has_custom_method_for_serialization? ||
          rule.multiple_mappings? || polymorphic_rule?(rule) ||
          (rule.transform.is_a?(Hash) && !rule.transform.empty?) ||
          rule.transform.is_a?(Class) || attr.nil? || attr.derived? ||
          attr.union? || attr.polymorphic? || attr.custom_collection? ||
          attr.transform ||
          rule.value_map(:to) != Lutaml::Model::Serialize::DEFAULT_VALUE_MAP

        @kv_serialize_plans ||= {}.compare_by_identity
        @kv_serialize_plans[rule] ||= KvSerializePlan.new(rule_from_name(rule))
      end

      def kv_rule_plan(format, rule, attr)
        @kv_rule_plans ||= {}
        @kv_rule_plans[[format, rule]] ||= build_kv_rule_plan(format, rule,
                                                              attr)
      end

      # `rule.polymorphic` defaults to an empty Hash, which is truthy —
      # presence is emptiness-based, mirroring MappingRule#polymorphic_mapping?.
      def polymorphic_rule?(rule)
        poly = rule.polymorphic
        poly.respond_to?(:empty?) ? !poly.empty? : !!poly
      end

      def build_kv_rule_plan(_format, rule, attr)
        return nil if rule.raw_mapping? ||
          rule.has_custom_method_for_deserialization? ||
          rule.hash_mappings || rule.multiple_mappings? ||
          polymorphic_rule?(rule) || rule.delegate ||
          (rule.transform.is_a?(Hash) && !rule.transform.empty?) ||
          rule.transform.is_a?(Class) ||
          attr.derived? ||
          attr.union? || attr.polymorphic? ||
          attr.custom_collection?

        type = attr.type(lutaml_register)
        return nil unless type.is_a?(Class) &&
          type < ::Lutaml::Model::Type::Value &&
          !attr.value_policy.whole_value?(type) &&
          !Lutaml::Model::Attribute.custom_from_probe?(type)

        KvRulePlan.new(rule.name.to_s, type, attr.collection?)
      end

      # Extraction fast path: plain hash fetch for a present, non-blank
      # value. nil/blank values keep the interpretive path — their
      # value-map/missing-value semantics must not be duplicated here.
      def kv_fast_extract(doc, plan)
        return nil unless doc.is_a?(::Hash)

        v = doc[plan.wire]
        return nil if v.nil?
        return nil if v.is_a?(::String) && v.empty?
        return nil if v.is_a?(::Array) && (v.empty? || !plan.collection)
        # Structured values on scalar plans keep the interpretive path —
        # its collection guidance error and cast semantics own them.
        return nil if v.is_a?(::Hash)

        v
      end

      # Cast fast path: identity when the value already has the target
      # class (the overwhelming case for engine-typed scalars), the type's
      # cast otherwise. Collections cast per element.
      def kv_fast_cast(value, plan, _instance)
        if plan.collection
          unless value.is_a?(::Array)
            return value.is_a?(plan.klass) ? value : plan.klass.cast(value)
          end

          klass = plan.klass
          value.map { |e| e.is_a?(klass) ? e : klass.cast(e) }
        else
          value.is_a?(plan.klass) ? value : plan.klass.cast(value)
        end
      end

      def cast_value(value, attr, format, rule, instance)
        cast_options = rule.polymorphic ? { polymorphic: rule.polymorphic } : {}
        cast_options[:lutaml_parent] = instance if instance
        if instance
          cast_options[:lutaml_root] =
            (instance.lutaml_root || instance)
        end
        attr.cast(value, format, lutaml_register, cast_options)
      end

      def translate_mappings(hash, child_mappings, attr, format, instance)
        return hash unless child_mappings

        hash.map do |key, value|
          process_child_mapping(key, value, child_mappings, attr, format, hash,
                                instance)
        end
      end

      def process_child_mapping(key, value, child_mappings, attr, format, hash,
instance)
        child_hash = build_child_hash(key, value, child_mappings, attr, format)

        if only_keys_mapped?(child_mappings, hash)
          child_hash.merge!(value)
        end

        map_child_data(child_hash, attr, format, instance)
      end

      def build_child_hash(key, value, child_mappings, attr, format)
        attr_type = attr.type(lutaml_register)
        child_mappings.to_h do |attr_name, path|
          attr_value = extract_attr_value(path, key, value)
          attr_rule = attr_type.mappings_for(format,
                                             lutaml_register).find_by_to!(attr_name)
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
        child_mappings.values == [:key] && hash.values.all?(::Hash)
      end

      def map_child_data(child_hash, attr, format, instance)
        attr_type = attr.type(lutaml_register)
        options = {
          mappings: attr_type.mappings_for(format, lutaml_register),
          lutaml_parent: instance,
          lutaml_root: instance.lutaml_root || instance,
        }
        self.class.data_to_model(attr_type, child_hash, format, options)
      end

      def rule_value_extractor_class
        Lutaml::Model::RuleValueExtractor
      end
    end
  end
end
