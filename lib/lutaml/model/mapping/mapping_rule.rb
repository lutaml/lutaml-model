module Lutaml
  module Model
    class MappingRule
      attr_reader :name,
                  :to,
                  :to_instance,
                  :as_attribute,
                  :render_nil,
                  :render_default,
                  :render_empty,
                  :treat_nil,
                  :treat_empty,
                  :treat_omitted,
                  :attribute,
                  :custom_methods,
                  :delegate,
                  :polymorphic,
                  :polymorphic_map,
                  :transform,
                  :format

      ALLOWED_OPTIONS = {
        render_nil: %i[
          omit
          as_nil
          as_blank
          as_empty
        ],
        render_empty: %i[
          omit
          as_empty
          as_blank
          as_nil
        ],
      }.freeze

      ALLOWED_OPTIONS.each do |key, values|
        attribute_name = key.to_s
        values.each do |value|
          define_method(:"#{attribute_name}_#{value}?") do
            send(attribute_name) == value
          end
        end
      end

      def initialize(
        name,
        to:,
        to_instance: nil,
        as_attribute: nil,
        render_nil: false,
        render_default: false,
        render_empty: false,
        treat_nil: :nil,
        treat_empty: :empty,
        treat_omitted: :nil,
        with: {},
        attribute: false,
        delegate: nil,
        root_mappings: nil,
        polymorphic: {},
        polymorphic_map: {},
        transform: {},
        value_map: {}
      )
        @name = name
        @to = to
        @to_instance = to_instance
        @as_attribute = as_attribute
        @render_nil = render_nil
        @render_default = render_default
        @render_empty = render_empty
        @treat_nil = treat_nil
        @treat_empty = treat_empty
        @treat_omitted = treat_omitted
        @custom_methods = with
        @attribute = attribute
        @delegate = delegate
        @root_mappings = root_mappings
        @polymorphic = polymorphic
        @polymorphic_map = polymorphic_map
        @transform = transform

        # Only calculate default_value_map if value_map is not fully provided
        if value_map.empty? || !value_map[:from] || !value_map[:to]
          # Build value_map by starting with defaults from render_nil/render_empty,
          # then overlaying user-provided value_map entries on top.
          # User-provided value_map entries take PRECEDENCE over computed defaults.
          # This ensures that value_map: { to: { empty: :empty } } overrides
          # the default render_empty: false → :omitted behavior.
          vm = {
            from: (value_map[:from] || {}).dup,
            to: (value_map[:to] || {}).dup,
          }
          defaults = default_value_map
          vm[:from] = defaults[:from].merge(vm[:from])
          vm[:to] = defaults[:to].merge(vm[:to])
          @value_map = vm
        else
          # Complete value_map provided (e.g., from deep_dup), use it directly.
          @value_map = value_map
        end

        # Freeze value_map and its inner hashes — they are never mutated after
        # construction, and downstream code reads them on every serialization.
        @value_map[:from].freeze
        @value_map[:to].freeze
        @value_map.freeze
      end

      def default_value_map(options = {})
        render_nil_as = render_as(:render_nil, :omitted, options)
        render_empty_as = render_as(:render_empty, :empty, options)

        treat_nil_as = treat_as(:treat_nil, :nil, options)
        treat_empty_as = treat_as(:treat_empty, :empty, options)
        treat_omitted_as = treat_as(:treat_omitted, :nil, options)

        {
          from: { omitted: treat_omitted_as, nil: treat_nil_as,
                  empty: treat_empty_as },
          to: { omitted: :omitted, nil: render_nil_as, empty: render_empty_as },
        }
      end

      def render_as(key, default_value, options = {})
        value = public_send(key)
        value = options[key] if value.nil?

        if value == true
          key.to_s.split("_").last.to_sym
        elsif value == false
          :omitted
        elsif value
          {
            as_empty: :empty,
            as_blank: :blank,
            as_nil: :nil,
            omit: :omitted,
          }[value]
        else
          default_value
        end
      end

      def treat_as(key, default_value, options = {})
        public_send(key) || options[key] || default_value
      end

      alias from name
      alias render_default? render_default
      alias attribute? attribute

      def render?(value, instance = nil, options = {})
        if invalid_value?(value, options)
          false
        # FIXED: Check if collection was mutated after initialization
        # A non-empty collection initialized with default [] should render if mutated
        # This handles the case where collection is mutated with << or custom methods
        elsif mutated_collection?(value, instance)
          true
        elsif RenderPolicy.derived_attribute_for?(instance, to)
          true
        elsif instance.respond_to?(:using_default?) && instance.using_default?(to)
          render_default?
        else
          true
        end
      end

      def treat?(value)
        if value.nil?
          treat_nil?
        elsif Utils.uninitialized?(value)
          treat_omitted?
        elsif Utils.empty?(value)
          treat_empty?
        else
          true
        end
      end

      def render_value_for(value)
        if value.nil?
          value_for_option(value_map(:to)[:nil])
        elsif Utils.empty?(value)
          value_for_option(value_map(:to)[:empty], value)
        elsif Utils.uninitialized?(value)
          value_for_option(value_map(:to)[:omitted])
        else
          value
        end
      end

      def mutated_collection?(value, instance)
        return false if value.nil? || Utils.uninitialized?(value)
        return false unless value.is_a?(Array) || value.is_a?(Lutaml::Model::Collection)
        return false if value.empty? # Empty collection is still default

        # If it's a non-empty collection and marked as using_default, it was mutated
        instance.respond_to?(:using_default?) && instance.using_default?(to)
      end

      # Check if value is a non-empty collection
      def has_items?(value)
        return false if value.nil? || Utils.uninitialized?(value)
        return false unless value.respond_to?(:empty?)

        !value.empty?
      end

      def value_for_option(option, empty_value = nil)
        return nil if option == :nil
        return empty_value || "" if option == :empty

        Lutaml::Model::UninitializedClass.instance
      end

      def render_nil?(options = {})
        value_map(:to, options)[:nil] != :omitted
      end

      def render_empty?(options = {})
        value_map(:to, options)[:empty] != :omitted
      end

      def render_omitted?(options = {})
        value_map(:to, options)[:omitted] != :omitted
      end

      def treat_nil?(options = {})
        value_map(:from, options)[:nil] != :omitted
      end

      def treat_empty?(options = {})
        value_map(:from, options)[:empty] != :omitted
      end

      def treat_omitted?(options = {})
        value_map(:from, options)[:omitted] != :omitted
      end

      def polymorphic_mapping?
        polymorphic_map && !polymorphic_map.empty?
      end

      def serialize_attribute(model, element, doc)
        if custom_methods[:to]
          model.send(custom_methods[:to], model, element, doc)
        end
      end

      def to_value_for(model)
        if delegate
          model.public_send(delegate).public_send(to)
        else
          return if to.nil?

          model.public_send(to)
        end
      end

      def serialize(model, parent = nil, doc = nil)
        if custom_methods[:to]
          model.send(custom_methods[:to], model, parent, doc)
        else
          value = to_value_for(model)

          # Handle Reference types - extract the key for serialization
          # This ensures references serialize as their key, not the resolved object
          if value.is_a?(Lutaml::Model::Type::Reference)
            value = value.key
          elsif value.is_a?(Array)
            # Handle collection of references
            value = value.map do |v|
              v.is_a?(Lutaml::Model::Type::Reference) ? v.key : v
            end
          end

          value
        end
      end

      def deserialize(model, value, attributes, mapper_class = nil)
        handle_custom_method(model, value, mapper_class) ||
          handle_delegate(model, value, attributes) ||
          handle_transform_method(model, value, attributes)
      end

      def has_custom_method_for_serialization?
        !custom_methods.empty? && custom_methods[:to]
      end

      def has_custom_method_for_deserialization?
        !custom_methods.empty? && custom_methods[:from]
      end

      def multiple_mappings?
        name.is_a?(Array)
      end

      def raw_mapping?
        name == Constants::RAW_MAPPING_KEY
      end

      def eql?(other)
        other.class == self.class &&
          instance_variables.all? do |var|
            instance_variable_get(var) == other.instance_variable_get(var)
          end
      end
      alias == eql?

      def deep_dup
        raise NotImplementedError, "Subclasses must implement `deep_dup`."
      end

      # Raw value_map hash access (for compiled rules).
      # Use value_map(key, options) for individual lookups with overrides.
      def raw_value_map
        @value_map
      end

      def value_map(key, options = {})
        # Fast path: when no overrides, return cached value directly
        # Callers MUST NOT mutate the returned hash
        if !options[:nil] && !options[:empty] && !options[:omitted]
          return @value_map[key]
        end

        # Slow path: merge overrides (only when options have actual values)
        overrides = {
          nil: options[:nil],
          empty: options[:empty],
          omitted: options[:omitted],
        }.compact

        @value_map[key].merge(overrides)
      end

      def transform_value(attribute, value, read_method, format)
        # Fast path: no transforms at all (covers 95%+ of rules)
        # transform defaults to {}, so check for actual content, not just truthiness
        has_rule_transform = transform.is_a?(Class)
        has_attr_transform = attribute&.transform.is_a?(Class)
        return value unless has_rule_transform || has_attr_transform

        transformers = get_transformers(attribute)
        transformers = transformers.reverse if read_method == :to

        return value if transformers.empty? || transformers.none? do |t|
          t.can_transform?(read_method, format)
        end

        # Apply transformers in sequence
        transformers.reduce(value) do |v, transformer|
          if transformer.is_a?(Class) && transformer < Lutaml::Model::ValueTransformer
            # Call class method directly: NameTransformer.from(value, :json)
          else
            # Hash/proc transformer
          end
          transformer.public_send(read_method, v, format)
        end
      end

      def can_transform_to?(attribute, format)
        get_transformers(attribute).any? { |t| t.can_transform?(:to, format) }
      end

      # Frozen empty array for the common case of no transformers
      EMPTY_TRANSFORMERS = [].freeze

      def get_transformers(attribute)
        # Fast path: most rules have no transforms at all
        rule_transform = transform
        attr_transform = attribute&.transform

        if !rule_transform && !attr_transform
          return EMPTY_TRANSFORMERS
        end

        # Build transformer list only when needed
        transformers = []
        transformers << rule_transform if rule_transform
        transformers << attr_transform if attr_transform
        transformers.select! { |t| t.is_a?(Class) }
        transformers.freeze
      end

      private

      # if value is nil and render nil is false, will not render
      # if value is empty and render empty is false, will not render
      # if value is uninitialized and render omitted is false, will not render
      def invalid_value?(value, options)
        if value.nil?
          !render_nil?(options)
        elsif Utils.empty?(value)
          !render_empty?(options)
        elsif Utils.uninitialized?(value)
          !render_omitted?(options)
        else
          false
        end
      end

      def handle_custom_method(model, value, mapper_class)
        return if !custom_methods[:from] || value.nil?

        mapper_class.new.send(custom_methods[:from], model, value)
        true
      end

      def handle_delegate(model, value, attributes)
        return unless delegate

        handle_nil_or_uninitialized(model, attributes)
        assign_value(model.public_send(delegate), value)
        true
      end

      def handle_nil_or_uninitialized(model, attributes)
        delegate_value = model.public_send(delegate)
        return if Utils.initialized?(delegate_value) && !delegate_value.nil?

        model.public_send(:"#{delegate}=",
                          attributes[delegate].type(model.lutaml_register).new)
      end

      def handle_transform_method(model, value, attributes)
        attr = attributes[to]
        # Fast path: no transforms at all (covers 95%+ of rules)
        # transform defaults to {} which is truthy but semantically empty
        rule_has_transform = transform.is_a?(Class) || (transform.is_a?(Hash) && !transform.empty?)
        attr_has_transform = attr&.transform && (attr.transform.is_a?(Class) || (attr.transform.is_a?(Hash) && !attr.transform.empty?))
        if !rule_has_transform && !attr_has_transform
          assign_value(model, value)
          return true
        end

        # If we have class-based transformers, they were already applied in transform_value
        # Only call ImportTransformer for hash/proc-based transformers
        transformers = get_transformers(attr)
        has_class_transformer = transformers.any? { |t| t.is_a?(Class) && t < Lutaml::Model::ValueTransformer }

        if has_class_transformer
          # Class transformers already applied, just assign the value
          assign_value(model, value)
        else
          # Hash/proc transformers need ImportTransformer
          transformed = ImportTransformer.call(value, self, attr)
          assign_value(model, transformed)
        end
        true
      end

      def assign_value(model, value)
        model.public_send(:"#{to}=", value)
      end
    end
  end
end
