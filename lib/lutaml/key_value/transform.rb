module Lutaml
  module KeyValue
    class Transform < Lutaml::Model::Transform
      def data_to_model(data, format, options = {})
        # Use child's own default register if it has one
        # This ensures versioned schemas (e.g., MML v2 with lutaml_default_register = :mml_v2)
        # are instantiated with their native context
        # TODO.max-perf/32: constant per (model class, register) — the
        # transform itself is cached per that pair, so resolve once.
        child_register = @kv_child_register ||= Lutaml::Model::Register
          .resolve_for_child(
            model_class, lutaml_register
          )

        # TODO.max-perf/37: eligible models hydrate in one pass —
        # collect raw values per rule, recurse into eligible child
        # models, build every instance through the bulk constructor.
        # Falls back to the per-rule walk for anything ineligible.
        if !options.key?(:mappings) && data.is_a?(::Hash) &&
            %i[json yaml toml hash].include?(format) &&
            (group = self.class.kv_group_plan(model_class, format,
                                              lutaml_register)) &&
            (instance = kv_group_build(group, data, format, child_register,
                                       options))
          root_and_parent_assignment(instance, options)
          return instance
        end

        if model_class.include?(Lutaml::Model::Serialize)
          instance = model_class.new(lutaml_register: child_register)
        else
          instance = model_class.new
          register_accessor_methods_for(instance, child_register)
        end
        root_and_parent_assignment(instance, options)
        mappings = extract_mappings(options, format)

        rules = mappings.mappings(lutaml_register)
        # lutaml-model#88: nil unless the mapping partitions a wire key
        # with when_attribute rules — the common case pays one scan.
        partition = kv_partition(rules)
        rules.each do |rule|
          process_mapping_rule(data, instance, format, rule, options, partition)
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

        rules = mappings.mappings(lutaml_register)
        partition = kv_partition(rules)
        hash = {}
        handled_groups = nil
        rules.each do |rule|
          next unless valid_mapping?(rule, options)

          group = partition && kv_partition_group(rule, partition)
          if group
            next if handled_groups&.include?(group)

            (handled_groups ||= []) << group
            process_partition_group!(instance, group, hash, format, options)
          else
            process_rule!(instance, rule, hash, format, mappings, options)
          end
        end

        hash.keys == [""] ? hash[""] : hash
      end

      # ---- TODO.max-perf/37: group-then-instantiate fast path ----

      # [model class, format, register] -> rows or false (ineligible).
      # Rows: [[rule, attr, kind, child_rows]] with kind :scalar or
      # :model; child_rows is the child model's own row set. Cycle-safe:
      # an in-progress model resolves false, so self-referential models
      # take the interpretive walk.
      # Concurrent::Map under threaded MRI, plain Hash under Opal
      # (Concurrent is unavailable there) — the RULE_RECORDS pattern.
      # Writes are idempotent (the same deterministic plan is computed),
      # so a lost race costs a duplicate build, never a wrong value.
      KV_GROUP_PLANS = if Lutaml::Model.opal?
                         {}
                       else
                         Lutaml::Model::RuntimeCompatibility
                           .require_native("concurrent")
                         Concurrent::Map.new
                       end

      def self.kv_group_plan(model_class, format, register)
        # Context generation: specs (and apps) reset registers between
        # parses; a plan cached across a reset references dead attribute
        # objects. The generation key retires stale plans for free.
        key = [model_class, format, register,
               Lutaml::Model::GlobalContext.context_generation]
        plan = KV_GROUP_PLANS[key]
        return plan unless plan.nil?

        # Cycle detection rides a THREAD-LOCAL recursion stack: a shared
        # in-progress set races (a concurrent same-key build would cache
        # false permanently), and the stack is per-build by definition.
        # The false at the cycle point is NOT cached — the outermost
        # build completes and caches the model's real verdict.
        stack = (Thread.current[:kv_group_plan_stack] ||= [])
        return false if stack.include?(key)

        stack.push(key)
        begin
          KV_GROUP_PLANS[key] = build_kv_group_plan(model_class, format,
                                                    register)
        ensure
          stack.pop
        end
      end

      def self.build_kv_group_plan(model_class, format, register)
        return false unless model_class.is_a?(Class) &&
          model_class.include?(Lutaml::Model::Serialize)

        mapping = model_class.mappings_for(format, register)
        return false if mapping.nil?

        attrs = model_class.attributes(register)
        rows = nil
        mapping.mappings(register).each do |rule|
          eligible = !rule.name.nil? && !rule.multiple_mappings? &&
            rule.delegate.nil? &&
            !rule.has_custom_method_for_deserialization? &&
            !rule.raw_mapping? && !rule.root_mapping? &&
            !rule.hash_mappings && rule.child_mappings.nil? &&
            rule.when_attribute.empty? &&
            !(if rule.polymorphic.is_a?(::Hash)
                !rule.polymorphic.empty?
              else
                !!rule.polymorphic
              end) &&
            rule.transform.is_a?(::Hash) && rule.transform.empty? &&
            rule.value_map(:from) ==
              Lutaml::Model::Serialize::DEFAULT_VALUE_MAP
          return false unless eligible

          attr = attrs[rule.to]
          return false if attr.nil? || attr.derived?
          # Declared ranges keep their eager validation on the
          # interpretive walk; polymorphic/union/custom-collection
          # dispatch and registered type substitutions own their cast
          # (the per-rule walk threads them through cast options).
          return false if attr.collection? && attr.collection.is_a?(Range)
          return false if attr.polymorphic? || attr.union? ||
            attr.custom_collection?

          type = attr.type(register)
          return false if Lutaml::Model::GlobalContext.context(register)
            .substitution_for(type).any?

          if type.is_a?(Class) && type.include?(Lutaml::Model::Serialize)
            child_rows = kv_group_plan(type, format,
                                       Lutaml::Model::Register
                                         .resolve_for_child(type, register))
            return false unless child_rows

            rows ||= []
            rows << [rule, attr, :model, type, child_rows]
          elsif type.is_a?(Class) && type < Lutaml::Model::Type::Value &&
              !attr.value_policy.whole_value?(type) &&
              !Lutaml::Model::Attribute.custom_from_probe?(type)
            rows ||= []
            rows << [rule, attr, :scalar, nil, nil]
          else
            return false
          end
        end
        # No eligible rows at all (empty mapping) — nothing to gain.
        rows
      end

      # Build values bottom-up, then ONE instance per model: present
      # keys through the casting setters, ABSENT rules through the real
      # per-rule walk (their extractor/defaults/sentinel semantics are
      # the walk's own — reproducing them here would fork them). The
      # per-rule walk is eliminated exactly for the present-key hot
      # path. Returns nil (caller falls back) on any shape the plan
      # does not cover, e.g. a non-Hash item where a model was expected.
      def kv_group_build(rows, doc, format, register, options)
        setters = []
        children = []
        absent = []
        rows.each do |rule, attr, kind, type, child_rows|
          unless Lutaml::Model::Utils.string_or_symbol_key?(doc, rule.name)
            absent << rule
            next
          end
          v = Lutaml::Model::Utils.fetch_str_or_sym(doc, rule.name)

          if kind == :scalar
            setters << [:"#{rule.to}=", v]
            next
          end

          child_register = Lutaml::Model::Register.resolve_for_child(type,
                                                                     register)
          if attr.collection?
            # A present-but-nil collection reaches the per-rule walk,
            # which owns the sentinel interplay for that edge
            # (render_nil :as_empty semantics).
            return nil if v.nil?

            items = v.is_a?(::Array) ? v : [v]
            built = []
            items.each do |item|
              return nil unless item.is_a?(::Hash)

              child = self.class.kv_group_instance(type, child_rows, item,
                                                   format, child_register,
                                                   options)
              return nil if child.nil?

              built << child
            end
            setters << [:"#{rule.to}=", built]
            children.concat(built)
          else
            return nil unless v.is_a?(::Hash)

            child = self.class.kv_group_instance(type, child_rows, v,
                                                 format, child_register,
                                                 options)
            return nil if child.nil?

            setters << [:"#{rule.to}=", child]
            children << child
          end
        end
        instance = model_class.new(lutaml_register: register)
        setters.each { |name, value| instance.public_send(name, value) }
        absent.each do |rule|
          process_mapping_rule(doc, instance, format, rule, options, nil)
        end
        children.each do |child|
          child.lutaml_parent = instance
          child.lutaml_root ||= instance.lutaml_root || instance
        end
        instance
      end

      def self.kv_group_instance(model_class, rows, doc, format, register,
options)
        # cached_transform is per (class, register); format rides the
        # call, not the cache.
        cached_transform(model_class, register)
          .kv_group_build(rows, doc, format, register, options)
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
        return false if rule.respond_to?(:serialize?) && !rule.serialize?

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

      # ---- lutaml-model#88: when_attribute for key-value formats ----

      # Wire keys partitioned by when_attribute rules: key -> { rules: all
      # rules on the key in declaration order, discriminators: the subset
      # carrying when_attribute }. nil unless any rule uses when_attribute.
      def kv_partition(rules)
        partitions = nil
        rules.each do |rule|
          next if rule.when_attribute.empty?

          partitions ||= {}
          key = kv_partition_key(rule)
          entry = (partitions[key] ||= { rules: [], discriminators: [] })
          entry[:discriminators] << rule
        end
        return nil unless partitions

        rules.each do |rule|
          key = kv_partition_key(rule)
          partitions[key][:rules] << rule if partitions.key?(key)
        end
        partitions
      end

      def kv_partition_key(rule)
        name = rule.name
        name = name.first if name.is_a?(Array)
        name.to_s
      end

      # The partition entry covering any of the rule's wire names.
      def kv_partition_group(rule, partition)
        return nil if partition.nil?

        if rule.multiple_mappings?
          rule.name.each do |name|
            entry = partition[name.to_s]
            return entry if entry
          end
          nil
        else
          partition[rule.name.to_s]
        end
      end

      # A value at a partitioned key, filtered for one rule: a
      # discriminator rule keeps its matches; a plain rule keeps the
      # occurrences no discriminator claimed (single-capture, mirroring
      # the XML side).
      def apply_kv_when_attribute(value, rule, entry, attr = nil)
        if rule.when_attribute.empty?
          return kv_partition_value(value, attr) do |item|
            entry[:discriminators].none? { |s| kv_item_matches?(item, s) }
          end
        end

        plain_sibling = entry[:rules].any? { |r| r.when_attribute.empty? }
        if rule.unmatched == :raise && !plain_sibling
          check_unclaimed_kv_items!(value, rule, entry)
        end
        kv_partition_value(value, attr) { |item| kv_item_matches?(item, rule) }
      end

      def kv_item_matches?(item, rule)
        return false unless item.is_a?(::Hash)

        rule.when_attribute.all? do |name, expected|
          actual = Lutaml::Model::Utils.fetch_str_or_sym(item, name.to_s)
          !actual.nil? && actual.to_s == expected.to_s
        end
      end

      # select/reject over the occurrence shape: an Array filters per
      # item; a single occurrence is kept or dropped as a whole; nil
      # passes through. A dropped occurrence existed on the wire, so a
      # collection attribute reads it as [] rather than absent. A
      # non-hash item satisfies no discriminator, so plain rules keep it
      # and discriminator rules drop it.
      def kv_partition_value(value, attr = nil, &block)
        case value
        when ::Array
          value.select(&block)
        when nil
          nil
        else
          if yield(value)
            value
          else
            attr&.collection? ? [] : nil
          end
        end
      end

      # lutaml-model#88: fail closed for `unmatched: :raise` — an item
      # no rule on the key claims is exactly the data the default
      # policy silently drops.
      def check_unclaimed_kv_items!(value, rule, entry)
        items = value.is_a?(::Array) ? value : [value]
        tested = entry[:discriminators].flat_map { |s| s.when_attribute.keys }
          .uniq.map(&:to_s)
        items.each do |item|
          next if entry[:discriminators].any? { |s| kv_item_matches?(item, s) }

          values = tested.filter_map do |name|
            v = item.is_a?(::Hash) &&
              Lutaml::Model::Utils.fetch_str_or_sym(item, name)
            "#{name}=#{v.inspect}" if v
          end
          raise ::Lutaml::Model::UnknownDiscriminatorError,
                "Item at <#{kv_partition_key(rule)}> (#{values.join(', ')}) " \
                "is claimed by no rule: it matches no when_attribute " \
                "discriminator and no plain rule shares the key. Cover the " \
                "value, add a plain rule, or opt out with unmatched: :drop"
        end
        nil
      end

      # Serialize a partitioned key as one wire value: every rule on the
      # key contributes its items in declaration order, each stamped with
      # its rule's discriminator pairs (unless the item already carries
      # the key — the value's own mapping wins).
      def process_partition_group!(instance, group, hash, format, options)
        wire = rule_from_name(group[:rules].first)
        items = []
        present = false
        group[:rules].each do |rule|
          next unless valid_mapping?(rule, options)

          scratch = {}
          process_mapping_for_instance(instance, scratch, format, rule, options)
          value = scratch[rule_from_name(rule)]
          next if value.nil?

          present = true
          Array(value).each do |item|
            items << kv_stamp_discriminator(item, rule)
          end
        end
        return unless present

        hash[wire] = items
      end

      def kv_stamp_discriminator(item, rule)
        return item unless item.is_a?(::Hash)

        missing = {}
        rule.when_attribute.each do |name, expected|
          unless Lutaml::Model::Utils.string_or_symbol_key?(item, name)
            missing[name.to_s] = expected.to_s
          end
        end
        missing.empty? ? item : item.merge(missing)
      end

      def process_mapping_rule(doc, instance, format, rule, options = {},
partition = nil)
        attr = attribute_for_rule(rule)
        return if attr&.derived?

        raise "Attribute '#{rule.to}' not found in #{self}" unless valid_rule?(
          rule, attr
        )

        # lutaml-model#88: discriminator rules (and plain rules on a
        # partitioned key) must filter the raw value, so they keep the
        # interpretive path.
        partitioned = partition && kv_partition_group(rule, partition)
        if partitioned.nil? && (plan = kv_rule_plan(format, rule, attr)) &&
            (value = kv_fast_extract(doc, plan))
          rule.deserialize(instance, kv_fast_cast(value, plan, instance),
                           attributes, self, options[:context], pre_cast: true)
          return
        end

        value = rule_value_extractor_class.call(rule, doc, format, attr,
                                                lutaml_register, options, instance)
        if partitioned && !Lutaml::Model::Utils.uninitialized?(value)
          value = apply_kv_when_attribute(value, rule, partitioned, attr)
        end
        value = apply_value_map(value, rule.value_map(:from, options), attr)

        if rule.has_custom_method_for_deserialization?
          # An empty value ("", [], {}) is a present value per the
          # missing-values semantics and must reach the custom method;
          # only nil (non-existent) skips it (lutaml-model#746).
          return if value.nil?

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
        # No pre_cast here: the interpretive attr.cast is not the full
        # cast chain — whole-value Type policies (e.g. a custom
        # Type::Value that receives the whole hash) are shaped by the
        # setter's cast_value, which must still run.
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
          rule.when_attribute? || rule.multiple_mappings? ||
          polymorphic_rule?(rule) ||
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
