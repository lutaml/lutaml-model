require_relative "../mapping/mapping_rule"
require "uri"

module Lutaml
  module Model
    module Xml
      class MappingRule < MappingRule
        attr_reader :namespace,
                    :prefix,
                    :namespace_class,
                    :namespace_param,
                    :mixed_content,
                    :default_namespace,
                    :cdata,
                    :as_list,
                    :delimiter,
                    :form,
                    :documentation

        def initialize(
          name,
          to:,
          render_nil: false,
          render_default: false,
          render_empty: false,
          treat_nil: nil,
          treat_empty: nil,
          treat_omitted: nil,
          with: {},
          delegate: nil,
          namespace: nil,
          mixed_content: false,
          cdata: false,
          namespace_set: false,
          attribute: false,
          default_namespace: nil,
          polymorphic: {},
          polymorphic_map: {},
          transform: {},
          value_map: {},
          as_list: nil,
          delimiter: nil,
          form: nil,
          documentation: nil
        )
          super(
            name,
            to: to,
            render_nil: render_nil,
            render_default: render_default,
            render_empty: render_empty,
            treat_nil: treat_nil,
            treat_empty: treat_empty,
            treat_omitted: treat_omitted,
            with: with,
            delegate: delegate,
            attribute: attribute,
            polymorphic: polymorphic,
            polymorphic_map: polymorphic_map,
            transform: transform,
            value_map: value_map,
          )

          # Store original namespace parameter to preserve :inherit symbol
          @namespace_param = namespace

          # Normalize namespace to XmlNamespace class
          @namespace_class = normalize_namespace(namespace)
          @namespace = @namespace_class == :blank ? nil : @namespace_class&.uri
          @prefix = @namespace_class == :blank ? nil : @namespace_class&.prefix_default
          @mixed_content = mixed_content
          @cdata = cdata

          @default_namespace = default_namespace

          @namespace_set = namespace_set
          @as_list = as_list
          @delimiter = delimiter
          @form = validate_form(form)
          @documentation = documentation
        end

        def namespace_set?
          !!@namespace_set
        end

        def content_mapping?
          name.nil?
        end

        def content_key
          cdata ? "#cdata-section" : "text"
        end

        def castable?
          !raw_mapping? && !content_mapping? && !custom_methods[:from]
        end

        def mixed_content?
          !!@mixed_content
        end

        # Check if this mapping specifies qualified form
        #
        # @return [Boolean] true if form is :qualified
        def qualified?
          form == :qualified
        end

        # Check if this mapping specifies unqualified form
        #
        # @return [Boolean] true if form is :unqualified
        def unqualified?
          form == :unqualified
        end

        # Check if form is explicitly set
        #
        # @return [Boolean] true if form option was provided
        def form_set?
          !form.nil?
        end

        def prefixed_name
          rule_name = multiple_mappings? ? name.first : name
          if prefix
            "#{prefix}:#{rule_name}"
          else
            rule_name
          end
        end

        def namespaced_names(parent_namespace = nil)
          if multiple_mappings?
            name.map do |rule_name|
              namespaced_name(parent_namespace, rule_name)
            end
          else
            names = [namespaced_name(parent_namespace)]

            # CRITICAL: When no explicit namespace is set and we're using parent/default namespace,
            # also include the unprefixed name. This handles cases where elements are unqualified
            # (element_form_default: :unqualified) but parent uses a namespace.
            # This allows matching both <Template> and <ns:Template> forms during parsing.
            if !namespace_set? && (parent_namespace || default_namespace)
              unprefixed = name.to_s
              names << unprefixed unless names.include?(unprefixed)
            end

            # For attributes with default_namespace, also include prefixed version
            # to support attribute_form_default :qualified during parsing
            if @attribute && default_namespace && !namespace_set?
              prefixed = "#{default_namespace}:#{name}"
              names << prefixed unless names.include?(prefixed)
            end

            names
          end
        end

        def namespaced_name(parent_namespace = nil, name = self.name)
          if name.to_s == "lang"
            Utils.blank?(prefix) ? name.to_s : "#{prefix}:#{name}"
          elsif @namespace_param == :inherit && parent_namespace
            # When namespace: :inherit, resolve to parent namespace for matching during deserialization
            "#{parent_namespace}:#{name}"
          elsif namespace_set? || @attribute
            [namespace, name].compact.join(":")
          elsif default_namespace
            "#{default_namespace}:#{name}"
          else
            [parent_namespace, name].compact.join(":")
          end
        end

        def deep_dup
          # Preserve @namespace_param exactly as it was (string, Class, :inherit, or nil)
          # This ensures the duplicate has the same internal state as the original
          ns_param = if @namespace_param.is_a?(Class) || @namespace_param == :inherit
                       # Classes and symbols are immutable, pass as-is
                       @namespace_param
                     else
                       # Strings need to be duplicated
                       @namespace_param&.dup
                     end

          self.class.new(
            name.dup,
            to: to,
            render_nil: render_nil,
            render_default: render_default,
            with: Utils.deep_dup(custom_methods),
            delegate: delegate,
            namespace: ns_param,
            mixed_content: mixed_content,
            cdata: cdata,
            namespace_set: namespace_set?,
            attribute: attribute,
            polymorphic: polymorphic.dup,
            default_namespace: default_namespace&.dup,
            transform: transform.dup,
            render_empty: render_empty.dup,
            value_map: Utils.deep_dup(@value_map),
            as_list: @as_list,
            delimiter: @delimiter,
            form: @form,
            documentation: @documentation,
          ).tap do |dup_rule|
            # Manually preserve the exact @namespace_class object to avoid
            # recreating anonymous classes (which would have different object_ids)
            dup_rule.instance_variable_set(:@namespace_class, @namespace_class)

            # Manually ensure @namespace and @prefix are new string objects
            if dup_rule.namespace
              dup_rule.instance_variable_set(:@namespace,
                                             dup_rule.namespace.dup)
            end
            if dup_rule.prefix
              dup_rule.instance_variable_set(:@prefix, dup_rule.prefix.dup)
            end
          end
        end

        # Resolve namespace for this mapping rule with W3C-compliant priority
        #
        # @param attr [Attribute] the attribute being mapped
        # @param register [Symbol, nil] register ID for type resolution
        # @param parent_ns_uri [String, nil] parent element's namespace URI
        # @param parent_ns_class [Class, nil] parent's XmlNamespace class
        # @param form_default [Symbol] :qualified or :unqualified from schema
        # @param use_prefix [Boolean, String, nil] whether to use prefix for this namespace
        # @param parent_prefix [String, nil] actual prefix parent is using (custom or default)
        # @return [Hash] namespace resolution result
        #   { uri: String|nil, prefix: String|nil, ns_class: Class|nil }
        def resolve_namespace(attr:, register: nil, parent_ns_uri: nil,
                            parent_ns_class: nil, form_default: :unqualified,
                            use_prefix: nil, parent_prefix: nil)
          if attribute?
            resolve_attribute_namespace(attr, register, parent_ns_class, form_default)
          else
            resolve_element_namespace(attr, register, parent_ns_uri,
                                      parent_ns_class, form_default, use_prefix,
                                      parent_prefix)
          end
        end

        private

        # Normalize namespace parameter to XmlNamespace class
        #
        # Converts various namespace formats to a consistent XmlNamespace class:
        # - XmlNamespace class: registered in registry and returned
        # - String URI: NO LONGER SUPPORTED - must use XmlNamespace class
        # - :inherit symbol: returns nil (handled specially in resolution)
        # - nil: returns nil
        #
        # @param namespace [Class, Symbol, nil] the namespace parameter
        # @return [Class, nil] XmlNamespace class or nil
        def normalize_namespace(namespace)
          return nil if namespace.nil?
          return :blank if namespace == :blank  # Store :blank symbol
          return nil if namespace.to_s == "inherit"  # :inherit handled in resolution

          # Named XmlNamespace class - register and return
          if namespace.is_a?(Class) && namespace < Lutaml::Model::XmlNamespace
            return NamespaceClassRegistry.instance.register_named(namespace)
          end

          # String URI - NO LONGER SUPPORTED
          # Kept for backward compatibility during migration only
          if namespace.is_a?(String)
            warn "[DEPRECATED] String namespace URIs are no longer supported. " \
                 "Define an XmlNamespace class instead. " \
                 "URI: #{namespace}"

            # Auto-generate prefix from last URI segment for backward compatibility
            auto_prefix = extract_prefix_from_uri(namespace)

            return NamespaceClassRegistry.instance.get_or_create(
              uri: namespace,
              prefix: auto_prefix,
              element_form_default: :qualified,
              attribute_form_default: :unqualified
            )
          end

          nil
        end

        # Well-known namespace URIs with standard prefixes
        WELL_KNOWN_NAMESPACES = {
          "http://www.w3.org/2001/XMLSchema-instance" => "xsi",
          "http://www.w3.org/2001/XMLSchema" => "xsd",
          "http://www.w3.org/1999/xhtml" => "html",
          "http://www.w3.org/XML/1998/namespace" => "xml",
        }.freeze

        # Extract prefix from URI for backward compatibility
        # Uses last segment of path, first 3 chars (or full if <= 4 chars)
        def extract_prefix_from_uri(uri_string)
          return nil if uri_string.nil? || uri_string.empty?

          # Check for well-known namespaces first
          return WELL_KNOWN_NAMESPACES[uri_string] if WELL_KNOWN_NAMESPACES.key?(uri_string)

          # Parse URI and get last path segment
          uri = URI.parse(uri_string)
          path_segments = uri.path.split('/').reject(&:empty?)

          if path_segments.empty?
            # Use last part of host if no path
            host_parts = (uri.host || '').split('.')
            segment = host_parts.first || 'ns'
          else
            segment = path_segments.last
          end

          # If segment contains hyphen, use first part
          segment = segment.split('-').first if segment.include?('-')

          # Clean up segment and lowercase
          clean_segment = segment.gsub(/[^a-zA-Z0-9]/, '').downcase
          return 'ns' if clean_segment.empty?

          # Use full segment if 4 chars or less, otherwise first 3 chars
          clean_segment.length <= 4 ? clean_segment : clean_segment[0, 3]
        end

        # Resolve namespace for XML attributes (W3C compliant)
        #
        # Priority:
        # 1. Explicit namespace in mapping (highest)
        # 2. Type-level namespace
        # 3. Schema-level attributeFormDefault :qualified
        # 4. NO NAMESPACE (W3C default - unprefixed attributes never inherit)
        #
        # @param attr [Attribute] the attribute
        # @param register [Symbol, nil] register ID
        # @param parent_ns_class [Class, nil] parent's XmlNamespace class
        # @param form_default [Symbol] :qualified or :unqualified from schema
        # @return [Hash] namespace info
        def resolve_attribute_namespace(attr, register, parent_ns_class = nil, form_default = :unqualified)
          # 0. HIGHEST: Explicit namespace: :blank
          if @namespace_param == :blank
            return {
              uri: nil,
              prefix: nil,
              ns_class: nil,
              explicit_blank: true
            }
          end

          # 1. Explicit mapping namespace
          if namespace_set? && @namespace_class
            return build_namespace_result_from_class(@namespace_class)
          end

          # 1.5. Form attribute override (overrides type namespace and schema defaults)
          if form == :unqualified
            return { uri: nil, prefix: nil, ns_class: nil }
          elsif form == :qualified && parent_ns_class
            return build_namespace_result_from_class(parent_ns_class)
          end

          # 2. Type-level namespace
          if attr && (type_ns_class = attr.type_namespace_class(register))
            result = build_namespace_result_from_class(type_ns_class)
            # CRITICAL W3C FLAG: Mark when attribute is in same namespace as parent with :unqualified
            # Serialization code will check this to omit prefix per attributeFormDefault
            if type_ns_class.uri == parent_ns_class&.uri && form_default == :unqualified
              result[:unqualified_same_ns] = true
            end
            return result
          end

          # 3. Schema-level attributeFormDefault :qualified
          # When schema specifies attributeFormDefault="qualified", attributes
          # must be qualified (prefixed) with the parent element's namespace
          if form_default == :qualified && parent_ns_class
            return build_namespace_result_from_class(parent_ns_class)
          end

          # 4. No namespace (W3C default for unprefixed attributes)
          { uri: nil, prefix: nil, ns_class: nil }
        end

        # Resolve namespace for XML elements
        #
        # Priority:
        # 1. Explicit namespace: nil (no namespace) - HIGHEST PRIORITY
        # 2. Explicit namespace: :inherit (parent namespace, overrides type)
        # 3. Explicit namespace class (specific namespace)
        # 4. Type-level namespace
        # 5. Form-based qualification (schema-level, not parent's format)
        # 6. No namespace (unqualified default)
        #
        # NOTE: use_prefix affects parent's declaration format, NOT child qualification
        #
        # @param attr [Attribute] the attribute
        # @param register [Symbol, nil] register ID
        # @param parent_ns_uri [String, nil] parent namespace URI
        # @param parent_ns_class [Class, nil] parent namespace class
        # @param form_default [Symbol] :qualified or :unqualified
        # @param use_prefix [Boolean, String, nil] parent's format (not used)
        # @param parent_prefix [String, nil] actual prefix parent is using
        # @return [Hash] namespace info
        def resolve_element_namespace(attr, register, parent_ns_uri,
                                     parent_ns_class, form_default, use_prefix = nil,
                                     parent_prefix = nil)
          # 0. HIGHEST: Explicit namespace: :blank
          if @namespace_param == :blank
            return {
              uri: nil,
              prefix: nil,
              ns_class: nil,
              explicit_blank: true  # Flag for xmlns="" generation
            }
          end

          # 1. FIRST: Check for explicit namespace: nil
          # This takes precedence over EVERYTHING - even type namespace
          if namespace_set? && @namespace.nil? && @namespace_param.nil?
            return { uri: nil, prefix: nil, ns_class: nil }
          end

          # 2. Explicit namespace: :inherit - Use parent namespace BEFORE checking type
          # This overrides any type-level namespace
          if @namespace_param == :inherit && parent_ns_uri
            effective_prefix = if parent_ns_class
                                 parent_prefix || parent_ns_class.prefix_default || prefix
                               else
                                 parent_prefix || prefix
                               end
            return build_namespace_result(parent_ns_uri, effective_prefix)
          end

          # 3. Explicit mapping namespace (namespace: SomeNamespace)
          if namespace_set? && @namespace_class
            return build_namespace_result_from_class(@namespace_class)
          end

          # 4. Type-level namespace
          if attr && (type_ns_class = attr.type_namespace_class(register))
            # Check if Type namespace matches parent default namespace
            # If so, use parent's namespace with parent's actual prefix
            if type_ns_class.uri == parent_ns_uri && parent_ns_class
              # Type matches parent namespace
              # If parent is using prefixed format (use_prefix: true), use parent's prefix
              # Otherwise, use nil prefix to inherit default namespace
              effective_prefix = use_prefix ? (parent_prefix || parent_ns_class&.prefix_default || prefix) : nil
              return build_namespace_result(parent_ns_uri, effective_prefix)
            end

            # Type namespace is different from parent, use Type's own namespace
            return build_namespace_result_from_class(type_ns_class)
          end

          # 5. Schema-level qualification rules
          #
          # At this point:
          # - No explicit namespace options (nil or :inherit)
          # - No type namespace, OR type namespace different from parent (already handled at step 3)
          #
          # Schema-level rules determine if element inherits parent namespace

          # A. Explicit form: :unqualified - NEVER qualify
          if unqualified?
            return { uri: nil, prefix: nil, ns_class: nil }
          end

          # B. Explicit form: :qualified OR schema default qualified
          # These elements inherit parent namespace
          # BUT don't inherit if namespace explicitly set to :blank
          will_inherit_from_schema = qualified? ||
            (form_default == :qualified && @namespace_param != :blank)
          if will_inherit_from_schema && parent_ns_uri
            # Format matching: use parent's format (prefix or default)
            # - If parent_prefix exists: parent is using prefix format, match it
            # - If use_prefix is true: explicitly request prefix format
            # - Otherwise: use default format (nil prefix)
            effective_prefix = if parent_prefix
                                 parent_prefix
                               elsif use_prefix
                                 parent_ns_class&.prefix_default || prefix
                               end
            return build_namespace_result(parent_ns_uri, effective_prefix)
          end

          # 6. No namespace (unqualified default)
          # Default W3C behavior: elements are unqualified unless schema says otherwise
          { uri: nil, prefix: nil, ns_class: nil }
        end

        # Build namespace result hash from XmlNamespace class
        #
        # @param ns_class [Class] XmlNamespace class
        # @return [Hash] namespace info
        def build_namespace_result_from_class(ns_class)
          {
            uri: ns_class.uri,
            prefix: ns_class.prefix_default,
            ns_class: ns_class,
          }
        end

        # Build namespace result hash from URI and prefix
        def build_namespace_result(uri, prefix)
          {
            uri: uri,
            prefix: prefix,
            ns_class: nil,
          }
        end

        # Validate form parameter
        #
        # @param form [Symbol, nil] the form value
        # @return [Symbol, nil] validated form value
        # @raise [ArgumentError] if form is invalid
        def validate_form(form)
          return nil if form.nil?

          valid_forms = %i[qualified unqualified]
          unless valid_forms.include?(form)
            raise ArgumentError,
                  "form must be :qualified or :unqualified, got #{form.inspect}"
          end

          form
        end
      end
    end
  end
end
