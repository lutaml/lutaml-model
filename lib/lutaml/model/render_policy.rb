# frozen_string_literal: true

module Lutaml
  module Model
    # Shared render policy mixin for determining what values to skip/render.
    #
    # Used by both Xml::Transformation and KeyValue::Transformation to provide
    # consistent behavior across serialization formats.
    #
    # Handles skip logic based on:
    # - render_nil and render_empty options
    # - value_map configurations
    # - Default value usage
    # - Collection handling
    module RenderPolicy
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

      # Check if nil value should be rendered
      #
      # @param rule [CompiledRule, MappingRule] The rule
      # @return [Boolean] true if nil should be rendered
      def render_nil?(rule)
        render_nil = extract_option(rule, :render_nil)
        return false if render_nil == :omit
        return true if render_nil == true
        return true if render_nil == :as_nil
        return true if render_nil == :as_empty
        return true if render_nil == :as_blank

        # Check value_map for nil handling
        value_map = extract_option(rule, :value_map) || {}
        to_map = value_map[:to] || value_map
        !%i[omit omitted].include?(to_map[:nil])
      end

      # Check if empty value should be rendered
      #
      # @param rule [CompiledRule, MappingRule] The rule
      # @return [Boolean] true if empty should be rendered
      def render_empty?(rule)
        render_empty = extract_option(rule, :render_empty)
        return false if render_empty == :omit
        return true if render_empty == true
        return true if render_empty == :as_nil
        return true if render_empty == :as_blank
        return true if render_empty == :as_empty

        # Check value_map for empty handling
        value_map = extract_option(rule, :value_map) || {}
        to_map = value_map[:to] || value_map
        !%i[omit omitted].include?(to_map[:empty])
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

        # Check render_nil and render_empty shortcuts FIRST
        # This ensures mutated collections with default values are still serialized
        case value
        when nil
          return should_skip_nil?(rule)
        when ->(v) { Lutaml::Model::Utils.empty?(v) }
          return should_skip_empty?(rule)
        when ->(v) { Lutaml::Model::Utils.uninitialized?(v) }
          return should_skip_uninitialized?(rule)
        end

        # Handle boolean value_map for true/false values
        # Only return early if should_skip_boolean? returns true
        # If it returns false, continue to should_skip_default? check
        boolean_result = should_skip_boolean?(value, rule)
        return true if boolean_result == true

        # Skip if context object is using default and render_default is false
        # But for collections, check if they were mutated (non-empty)
        should_skip_default?(value, rule, context_obj, attr_name)
      end

      # Check if nil value should be skipped
      #
      # @param rule [CompiledRule, MappingRule] The rule
      # @return [Boolean] true if should skip
      def should_skip_nil?(rule)
        render_nil = extract_option(rule, :render_nil)
        return true if render_nil == :omit
        return false if render_nil == true
        return false if render_nil == :as_nil
        return false if render_nil == :as_empty
        return false if render_nil == :as_blank

        # Fall back to value_map
        value_map = extract_option(rule, :value_map) || {}
        to_map = value_map[:to] || value_map
        %i[omit omitted].include?(to_map[:nil])
      end

      # Check if empty value should be skipped
      #
      # @param rule [CompiledRule, MappingRule] The rule
      # @return [Boolean] true if should skip
      def should_skip_empty?(rule)
        render_empty = extract_option(rule, :render_empty)
        return true if render_empty == :omit
        return false if render_empty == true
        return false if render_empty == :as_nil
        return false if render_empty == :as_blank
        return false if render_empty == :as_empty

        # For false or unset, default to skipping empty values (legacy behavior)
        value_map = extract_option(rule, :value_map) || {}
        to_map = value_map[:to] || value_map
        %i[omit omitted].include?(to_map[:empty])
      end

      # Check if uninitialized value should be skipped
      #
      # @param rule [CompiledRule, MappingRule] The rule
      # @return [Boolean] true if should skip
      def should_skip_uninitialized?(rule)
        value_map = extract_option(rule, :value_map) || {}
        to_map = value_map[:to] || value_map
        # Return true to skip if:
        # - to_map[:omitted] is nil (not set, so default to omit)
        # - to_map[:omitted] is explicitly set to :omit (legacy format)
        # - to_map[:omitted] is explicitly set to :omitted (new format)
        # Return false to render if to_map[:omitted] is set to something else
        to_map[:omitted].nil? || %i[omit omitted].include?(to_map[:omitted])
      end

      # Check if boolean value should be skipped based on value_map
      #
      # @param value [Boolean] The boolean value
      # @param rule [CompiledRule, MappingRule] The rule
      # @return [Boolean, nil] true if should skip, false if should render,
      #   nil to continue
      def should_skip_boolean?(value, rule)
        return false unless value.is_a?(TrueClass) || value.is_a?(FalseClass)

        value_map = extract_option(rule, :value_map) || {}
        boolean_key = value ? true : false
        if value_map[:to] && value_map[:to][boolean_key]
          mapped_value = value_map[:to][boolean_key]
          return true if mapped_value == :omitted
        end
        false
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
        if context_obj.respond_to?(:using_default?) &&
            context_obj.using_default?(attr_name) &&
            !extract_option(rule, :render_default)
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
        if rule.respond_to?(:option)
          rule.option(option_name)
        elsif rule.respond_to?(option_name)
          rule.send(option_name)
        end
      end

      # Extract attribute name from rule
      #
      # @param rule [CompiledRule, MappingRule] The rule
      # @return [Symbol] The attribute name
      def extract_attribute_name(rule)
        if rule.respond_to?(:attribute_name)
          rule.attribute_name
        elsif rule.respond_to?(:to)
          rule.to
        end
      end

      # Check if rule defines a collection
      #
      # @param rule [CompiledRule, MappingRule] The rule
      # @return [Boolean] true if collection
      def collection?(rule)
        if rule.respond_to?(:collection?)
          rule.collection?
        else
          false
        end
      end
    end
  end
end
