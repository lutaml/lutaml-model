# frozen_string_literal: true

module Lutaml
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
                    :parent_namespace_prefix,
                    :parent_hoisted,
                    :namespace_class,
                    :namespace_uri,
                    :namespace_key,
                    :element_used_prefix

        def initialize(element:, mapping:, needs:, options: {},
                       is_root: false,
                       parent_format: nil,
                       parent_namespace_class: nil,
                       parent_namespace_prefix: nil,
                       parent_hoisted: {},
                       element_used_prefix: nil)
          @element = element
          @mapping = mapping
          @needs = needs
          @options = options
          @is_root = is_root
          @parent_format = parent_format
          @parent_namespace_class = parent_namespace_class
          @parent_namespace_prefix = parent_namespace_prefix
          @parent_hoisted = parent_hoisted || {}
          @element_used_prefix = element_used_prefix

          # Extract namespace info from element
          @namespace_class = element&.namespace_class
          @namespace_uri = @namespace_class&.uri
          @namespace_key = @namespace_class&.to_key

          freeze
        end

        # Check if this is the root element
        def root?
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
        #
        # Checks both:
        # 1. input_formats[uri] - namespace-level format (root-level namespaces)
        # 2. input_prefix_formats[prefix:uri] - per-prefix format (for child element namespaces)
        #
        # NOTE: Only check input_prefix_formats when the element has an explicit prefix.
        # If the element has no prefix (namespace inherited or default), use input_formats.
        def preserved_input_format
          return nil unless @namespace_uri
          return nil unless @options[:input_formats]

          # First try namespace-level format (root-level)
          format = @options[:input_formats][@namespace_uri]
          return format if format

          # Fall back to per-prefix format ONLY if this element has an explicit prefix.
          # This handles the case where a child element declares its own namespace
          # with a specific prefix (e.g., <xhtml:div xmlns:xhtml="...">).
          # If the element has no explicit prefix, the namespace was either inherited
          # from parent or declared at root level, so we should use input_formats.
          prefix = element_namespace_prefix
          return nil unless prefix && !prefix.empty?

          # Look up input_prefix_formats directly from stored plan
          input_prefix_formats = @options[:stored_xml_declaration_plan]&.input_prefix_formats
          return nil unless input_prefix_formats

          # Look up prefix:uri format, trying all URIs (canonical + aliases)
          # This handles the case where input XML used an alias URI but the model
          # uses canonical URI (or vice versa).
          all_uris = @namespace_class&.all_uris || [@namespace_uri]
          all_uris.each do |uri|
            key = "#{prefix}:#{uri}"
            format = input_prefix_formats[key]
            return format if format
          end

          nil
        end

        # Get the namespace prefix from the element
        # Works for both Lutaml::Xml::XmlElement (from parsed XML) and
        # DataModel::XmlElement (from serialization transform)
        #
        # For DataModel::XmlElement, first checks @__xml_namespace_prefix.
        # If not set, falls back to checking @__original_xml_element which
        # preserves the original Lutaml::Xml::XmlElement wrapper from parsing.
        def element_namespace_prefix
          return nil unless @element

          if @element.is_a?(Lutaml::Xml::XmlElement)
            @element.namespace_prefix if @element.respond_to?(:namespace_prefix)
          else
            # For DataModel::XmlElement, check xml_namespace_prefix first
            prefix = @element.xml_namespace_prefix
            return prefix if prefix && !prefix.empty?

            # Fall back to original XmlElement wrapper if available
            original = @element.original_xml_element
            if original.respond_to?(:namespace_prefix)
              return original.namespace_prefix
            end

            nil
          end
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

        # Check if there are Type namespaces that need prefix format
        # Type namespaces are declared on parent and used by child elements
        def has_type_namespaces?
          return false unless @needs

          @needs.type_refs.any?
        end
      end
    end
  end
end
