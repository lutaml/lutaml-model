# frozen_string_literal: true

module Lutaml
  module Model
    class Transform
      # Maximum number of cached Transform instances before eviction.
      # Covers most OOXML/ISO schemas with ~1000+ classes and multiple registers.
      MAX_CACHE_SIZE = 2048

      # The (lane, context, register) memo lives in a shared constant,
      # not in class-level ivars: KeyValue::Transform subclasses this
      # class, and inherited class methods run with the subclass as
      # self — ivar state forked per subclass, and clear_cache! on the
      # base class never reached the subclass's copy (stale compiled
      # plans across register resets). The lane is part of the key:
      # each transform class compiles format-specific rules, so a KV
      # transform and the base one must never answer for each other.
      class TransformCache
        attr_reader :size

        def initialize
          @entries = {}
          @size = 0
        end

        # Nested memo, not an array key: the hot path is one lookup per
        # parsed node and the key array was that lookup's only
        # allocation (60k arrays on a 6k-node corpus).
        def fetch_or_store(lane, context, register)
          by_context = @entries[lane]
          by_register = by_context&.[](context)
          return by_register[register] if by_register&.key?(register)

          by_register = ((@entries[lane] ||= {})[context] ||= {})
          transform = yield
          by_register[register] = transform
          @size += 1
          transform
        end

        def evict_half_if_full
          return unless @size >= MAX_CACHE_SIZE

          drop = @size / 2
          @entries.each do |lane, by_context|
            by_context.each do |ctx, by_register|
              break if drop <= 0

              drop -= by_register.size
              by_context.delete(ctx)
            end
            @entries.delete(lane) if by_context.empty?
            break if drop <= 0
          end
          @size = @entries.sum { |_, by_context| by_context.sum { |_, br| br.size } }
        end

        def invalidate(context, register = nil)
          @entries.each_value do |by_context|
            if register
              by_register = by_context[context]
              next unless by_register&.delete(register)

              @size -= 1
              by_context.delete(context) if by_register.empty?
            else
              removed = by_context.delete(context)
              @size -= removed.size if removed
            end
          end
        end

        def clear
          @entries.clear
          @size = 0
        end
      end

      TRANSFORM_CACHE = TransformCache.new

      def self.data_to_model(context, data, format, options = {})
        register = options[:register] || Lutaml::Model::Config.default_register
        transform = cached_transform(context, register, options[:mappings])
        transform.data_to_model(data, format, options)
      end

      def self.model_to_data(context, model, format, options = {})
        register = model.lutaml_register if model.is_a?(Lutaml::Model::Serialize)
        register ||= Lutaml::Model::Config.default_register
        transform = cached_transform(context, register, options[:mappings])
        transform.model_to_data(model, format, options)
      end

      # An explicit mapping (#176 `mapping:` profiles / `mappings:` seam)
      # gets a dedicated transform so per-instance compiled state (walk
      # plans, serialize plans) never mixes with the base mapping's.
      def self.cached_transform(context, register, mappings = nil)
        return override_transform(context, register, mappings) if mappings

        TRANSFORM_CACHE.evict_half_if_full
        TRANSFORM_CACHE.fetch_or_store(self, context, register) do
          new(context, register)
        end
      end

      def self.override_transform(context, register, mappings)
        @override_transform_cache ||= {}
        cache_key = [context, register, mappings.object_id]
        entry = @override_transform_cache[cache_key]
        return entry if entry

        evict_override_if_needed if @override_transform_cache.size >= MAX_CACHE_SIZE
        @override_transform_cache[cache_key] = new(context, register, mappings)
      end

      def self.evict_override_if_needed
        keys = @override_transform_cache.keys.first(@override_transform_cache.size / 2)
        keys.each { |k| @override_transform_cache.delete(k) }
      end
      private_class_method :evict_override_if_needed

      def self.clear_cache!
        TRANSFORM_CACHE.clear
        @override_transform_cache&.clear
      end

      def self.cache_size
        TRANSFORM_CACHE.size
      end

      def self.invalidate_for(context, register = nil)
        TRANSFORM_CACHE.invalidate(context, register)
      end

      attr_reader :context, :lutaml_register

      def initialize(context, register = nil, mappings_override = nil)
        @context = context
        @lutaml_register = register || Lutaml::Model::Config.default_register
        @lutaml_mapping_override = mappings_override
      end

      def attributes
        context.attributes(lutaml_register)
      end

      def model_class
        @context.model
      end

      def data_to_model(data, options = {})
        raise NotImplementedError,
              "#{self.class.name} must implement `data_to_model`."
      end

      def model_to_data(model, options = {})
        raise NotImplementedError,
              "#{self.class.name} must implement `model_to_data`."
      end

      protected

      def apply_value_map(value, value_map, attr)
        return attr.apply_value_map(value, value_map) if attr

        # Attribute-less dispatch for custom-method-only rules. Mirrors
        # Attribute#apply_value_map for the options that need no attribute
        # info: :nil -> nil and :omitted -> uninitialized. A typed :empty needs
        # an Attribute (a crash case pre-consolidation), so the value passes
        # through unchanged.
        key = if value.nil? then :nil
              elsif Utils.empty?(value) then :empty
              elsif Utils.uninitialized?(value) then :omitted
              end
        return value unless key

        case value_map[key]
        when :nil then nil
        when :empty then value
        else Lutaml::Model::UninitializedClass.instance
        end
      end

      def mappings_for(format, register = nil)
        return @lutaml_mapping_override if @lutaml_mapping_override

        context.mappings_for(format, register)
      end

      def defined_mappings_for(format)
        context.mappings[format]
      end

      def valid_rule?(rule, attribute)
        attribute || rule.custom_methods[:from]
      end

      def attribute_for_rule(rule)
        return attributes[rule.to] unless rule.delegate

        attributes[rule.delegate].type(lutaml_register).attributes[rule.to]
      end

      def register_accessor_methods_for(object, register)
        klass = object.class
        Utils.add_method_if_not_defined(klass, :lutaml_register) do
          @lutaml_register
        end
        Utils.add_method_if_not_defined(klass, :lutaml_register=) do |value|
          @lutaml_register = value
        end
        object.lutaml_register = register
      end

      def root_and_parent_assignment(instance, options)
        root_and_parent_accessor_methods_for(instance)
        return unless options.key?(:lutaml_parent) && options.key?(:lutaml_root)

        instance.lutaml_root = options[:lutaml_root] || options[:lutaml_parent]
        instance.lutaml_parent = options[:lutaml_parent]
      end

      def root_and_parent_accessor_methods_for(instance)
        Utils.add_accessor_if_not_defined(instance.class, :lutaml_parent)
        Utils.add_accessor_if_not_defined(instance.class, :lutaml_root)
      end
    end
  end
end
