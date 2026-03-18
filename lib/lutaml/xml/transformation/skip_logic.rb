# frozen_string_literal: true

module Lutaml
  module Xml
    module TransformationSupport
      # Module for determining if values should be skipped during serialization.
      #
      # Delegates to the shared Lutaml::Model::RenderPolicy module for
      # consistent behavior across XML and KeyValue formats.
      #
      # Handles skip logic based on:
      # - render_nil and render_empty options
      # - value_map configurations
      # - Default value usage
      # - Collection handling
      module SkipLogic
        include Lutaml::Model::RenderPolicy

        # Check if value should be skipped based on render options
        #
        # @param value [Object] The value to check
        # @param rule [CompiledRule] The rule
        # @param model_instance [Object] The model instance
        # @return [Boolean] true if should skip
        def should_skip_value?(value, rule, model_instance)
          check_skip_logic?(value, rule, model_instance)
        end

        # Check if delegated value should be skipped
        #
        # @param value [Object] The value to check
        # @param rule [CompiledRule] The rule
        # @param delegate_obj [Object] The delegated object instance
        # @return [Boolean] true if should skip
        def should_skip_delegated_value?(value, rule, delegate_obj)
          return true if delegate_obj.nil?

          check_skip_logic?(value, rule, delegate_obj)
        end

        private

        # Extract option from CompiledRule
        #
        # @param rule [CompiledRule] The rule
        # @param option_name [Symbol] The option name
        # @return [Object, nil] The option value
        def extract_option(rule, option_name)
          rule.option(option_name)
        end

        # Extract attribute name from CompiledRule
        #
        # @param rule [CompiledRule] The rule
        # @return [Symbol] The attribute name
        def extract_attribute_name(rule)
          rule.attribute_name
        end

        # Check if rule defines a collection
        #
        # @param rule [CompiledRule] The rule
        # @return [Boolean] true if collection
        def collection?(rule)
          rule.collection?
        end
      end
    end
  end
end
