# frozen_string_literal: true

require_relative "decision"

module Lutaml
  module Model
    module Xml
      module Decisions
        # Immutable value object containing all context needed for decisions
        #
        # This is the ONLY source of truth for decision-making context.
        # All decision rules read from this context, never from external state.
        class DecisionContext
          attr_reader :element,
                     :mapping,
                     :needs,
                     :options,
                     :is_root,
                     :parent_format,
                     :parent_namespace_class,
                     :parent_hoisted,
                     :namespace_class,
                     :namespace_uri,
                     :namespace_key

          def initialize(element:, mapping:, needs:, options: {},
                         is_root: false,
                         parent_format: nil,
                         parent_namespace_class: nil,
                         parent_hoisted: {})
            @element = element
            @mapping = mapping
            @needs = needs
            @options = options
            @is_root = is_root
            @parent_format = parent_format
            @parent_namespace_class = parent_namespace_class
            @parent_hoisted = parent_hoisted || {}

            # Extract namespace info from element
            @namespace_class = element&.namespace_class
            @namespace_uri = @namespace_class&.uri
            @namespace_key = @namespace_class&.to_key

            freeze
          end

          # Check if this is the root element
          def is_root?
            @is_root
          end

          # Check if element has a namespace
          def has_namespace?
            !@namespace_class.nil?
          end

          # Get namespace usage for this element's namespace
          def namespace_usage
            return nil unless @namespace_key
            @needs.namespace(@namespace_key)
          end

          # Check if namespace is used in attributes
          def used_in_attributes?
            usage = namespace_usage
            usage&.used_in_attributes?
          end

          # Check if namespace is used in elements
          def used_in_elements?
            usage = namespace_usage
            usage&.used_in_elements?
          end

          # Check if input format is preserved for this namespace
          def preserved_input_format
            return nil unless @namespace_uri
            return nil unless @options[:input_formats]
            @options[:input_formats][@namespace_uri]
          end

          # Check if explicit prefix option is set
          # NOTE: serialize.rb converts :prefix to :use_prefix, so we check that
          def explicit_prefix_option
            @options[:use_prefix]
          end

          # Check if namespace is in namespace_scope
          def namespace_scope_config
            return nil unless @namespace_class
            @needs.scope_config_for(@namespace_class)
          end

          # Check if parent uses default format
          def parent_uses_default_format?
            @parent_format == :default
          end

          # Check if element is in same namespace as parent
          def same_namespace_as_parent?
            return false unless @namespace_class
            return false unless @parent_namespace_class
            @namespace_key == @parent_namespace_class.to_key
          end

          # Check if namespace is hoisted on parent
          def hoisted_on_parent?
            return false unless @namespace_uri
            @parent_hoisted.any? { |_prefix, uri| uri == @namespace_uri }
          end

          # Get the prefix that was hoisted on parent
          def hoisted_prefix_on_parent
            return nil unless @namespace_uri
            @parent_hoisted.find { |_prefix, uri| uri == @namespace_uri }&.first
          end

          # Check if element's namespace matches parent's default namespace
          # This handles the case where parent has xmlns="uri" and child is in that namespace
          def namespace_matches_parent_default?
            return false unless @namespace_uri
            return false unless @parent_hoisted.key?(nil)
            @parent_hoisted[nil] == @namespace_uri
          end
        end
      end
    end
  end
end
