# frozen_string_literal: true

module Lutaml
  module Model
    # Shared render policy mixin for determining what values to skip/render.
    #
    # Used by both Xml::Transformation and KeyValue::Transformation to provide
    # consistent behavior across serialization formats.
    #
    # All render/skip decisions are made through the value_map, which is the
    # single source of truth. The user-facing render_nil/render_empty DSL
    # options are normalized into value_map entries at MappingRule construction
    # time, so downstream code never needs to re-interpret them.
    module RenderPolicy
      def self.derived_attribute_for?(context_obj, attr_name)
        return false unless context_obj.is_a?(Lutaml::Model::Serialize) &&
          context_obj.class.is_a?(Class) &&
          context_obj.class.include?(Lutaml::Model::Serialize)

        register = context_obj.lutaml_register
        context_obj.class.attributes(register)&.[](attr_name)&.derived?
      end

      # Check if value should be skipped based on render options
      #
      # @param value [Object] The value to check
      # @param rule [CompiledRule, MappingRule] The rule
      # @param model_instance [Object] The model instance
      # @return [Boolean] true if should skip
      def should_skip_value?(value, rule, model_instance)
        check_skip_logic?(value, rule, model_instance)
      end

      # Check if delegated value should be skipped
      #
      # @param value [Object] The value to check
      # @param rule [CompiledRule, MappingRule] The rule
      # @param delegate_obj [Object] The delegated object instance
      # @return [Boolean] true if should skip
      def should_skip_delegated_value?(value, rule, delegate_obj)
        return true if delegate_obj.nil?

        check_skip_logic?(value, rule, delegate_obj)
      end

      private

      # Unified skip logic check
      #
      # @param value [Object] The value to check
      # @param rule [CompiledRule, MappingRule] The rule
      # @param context_obj [Object] The context object (model_instance or delegate_obj)
      # @return [Boolean] true if should skip
      def check_skip_logic?(value, rule, context_obj)
        attr_name = extract_attribute_name(rule)

        to_map = to_value_map(rule)

        case value
        when nil
          return to_map[:nil] == :omitted
        when ->(v) { Lutaml::Model::Utils.empty?(v) }
          return to_map[:empty] == :omitted
        when ->(v) { Lutaml::Model::Utils.uninitialized?(v) }
          return to_map[:omitted] == :omitted || to_map[:omitted].nil?
        end

        # Handle boolean value_map for true/false values
        if (value.is_a?(TrueClass) || value.is_a?(FalseClass)) && to_map[value] && (to_map[value] == :omitted)
          return true
        end

        # Skip if context object is using default and render_default is false
        # But for collections, check if they were mutated (non-empty)
        should_skip_default?(value, rule, context_obj, attr_name)
      end

      # Extract the :to value_map from a rule
      #
      # @param rule [CompiledRule, MappingRule] The rule
      # @return [Hash] The :to value map
      def to_value_map(rule)
        vm = extract_option(rule, :value_map)
        vm[:to] || vm || {}
      end

      # Check if value using default should be skipped
      #
      # @param value [Object] The value
      # @param rule [CompiledRule, MappingRule] The rule
      # @param context_obj [Object] The context object
      # @param attr_name [Symbol] The attribute name
      # @return [Boolean] true if should skip
      def should_skip_default?(value, rule, context_obj, attr_name)
        # Skip if context object is using default and render_default is false
        # But for collections, check if they were mutated (non-empty)
        if context_obj.is_a?(Lutaml::Model::Serialize) &&
            context_obj.using_default?(attr_name) &&
            !extract_option(rule, :render_default)
          return false if derived_attribute?(context_obj, attr_name)

          # For collections: if mutated to non-empty, serialize them
          # For scalars: skip if using default
          if collection?(rule)
            return false unless Lutaml::Model::Utils.empty?(value)
          else
            return true
          end
        end

        false
      end

      # Extract option from rule (works with CompiledRule or MappingRule)
      #
      # @param rule [CompiledRule, MappingRule] The rule
      # @param option_name [Symbol] The option name
      # @return [Object, nil] The option value
      def extract_option(rule, option_name)
        if rule.is_a?(CompiledRule)
          rule.option(option_name)
        elsif rule.is_a?(MappingRule)
          rule.public_send(option_name)
        end
      end

      def extract_attribute_name(rule)
        if rule.is_a?(CompiledRule)
          rule.attribute_name
        else
          rule.to
        end
      end

      def collection?(rule)
        if rule.is_a?(CompiledRule) || rule.is_a?(MappingRule)
          rule.collection?
        else
          false
        end
      end

      def derived_attribute?(context_obj, attr_name)
        RenderPolicy.derived_attribute_for?(context_obj, attr_name)
      end
    end
  end
end
