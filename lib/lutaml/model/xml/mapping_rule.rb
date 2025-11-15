require_relative "../mapping/mapping_rule"

module Lutaml
  module Model
    module Xml
      class MappingRule < MappingRule
        attr_reader :namespace,
                    :prefix,
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
          prefix: nil,
          mixed_content: false,
          cdata: false,
          namespace_set: false,
          prefix_set: false,
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

          @namespace = if namespace.to_s == "inherit"
                       # we are using inherit_namespace in xml builder by
                       # default so no need to do anything here.
                       else
                         namespace
                       end
          @prefix = prefix
          @mixed_content = mixed_content
          @cdata = cdata

          @default_namespace = default_namespace

          @namespace_set = namespace_set
          @prefix_set = prefix_set
          @as_list = as_list
          @delimiter = delimiter
          @form = validate_form(form)
          @documentation = documentation
        end

        def namespace_set?
          !!@namespace_set
        end

        def prefix_set?
          !!@prefix_set
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
            [namespaced_name(parent_namespace)]
          end
        end

        def namespaced_name(parent_namespace = nil, name = self.name)
          if name.to_s == "lang"
            Utils.blank?(prefix) ? name.to_s : "#{prefix}:#{name}"
          elsif namespace_set? || @attribute
            [namespace, name].compact.join(":")
          elsif default_namespace
            "#{default_namespace}:#{name}"
          else
            [parent_namespace, name].compact.join(":")
          end
        end

        def deep_dup
          self.class.new(
            name.dup,
            to: to,
            render_nil: render_nil,
            render_default: render_default,
            with: Utils.deep_dup(custom_methods),
            delegate: delegate,
            namespace: namespace.dup,
            prefix: prefix.dup,
            mixed_content: mixed_content,
            cdata: cdata,
            namespace_set: namespace_set?,
            prefix_set: prefix_set?,
            attribute: attribute,
            polymorphic: polymorphic.dup,
            default_namespace: default_namespace.dup,
            transform: transform.dup,
            render_empty: render_empty.dup,
            value_map: Utils.deep_dup(@value_map),
            as_list: @as_list,
            delimiter: @delimiter,
            form: @form,
            documentation: @documentation,
          )
        end

        # Resolve namespace for this mapping rule with W3C-compliant priority
        #
        # @param attr [Attribute] the attribute being mapped
        # @param register [Symbol, nil] register ID for type resolution
        # @param parent_ns_uri [String, nil] parent element's namespace URI
        # @param parent_ns_class [Class, nil] parent's XmlNamespace class
        # @param form_default [Symbol] :qualified or :unqualified from schema
        # @return [Hash] namespace resolution result
        #   { uri: String|nil, prefix: String|nil, ns_class: Class|nil }
        def resolve_namespace(attr:, register: nil, parent_ns_uri: nil,
                            parent_ns_class: nil, form_default: :unqualified)
          if attribute?
            resolve_attribute_namespace(attr, register)
          else
            resolve_element_namespace(attr, register, parent_ns_uri,
                                      parent_ns_class, form_default)
          end
        end

        private

        # Resolve namespace for XML attributes (W3C compliant)
        #
        # Priority:
        # 1. Explicit namespace in mapping (highest)
        # 2. Type-level namespace
        # 3. NO NAMESPACE (W3C default - unprefixed attributes never inherit)
        #
        # @param attr [Attribute] the attribute
        # @param register [Symbol, nil] register ID
        # @return [Hash] namespace info
        def resolve_attribute_namespace(attr, register)
          # 1. Explicit mapping namespace
          if namespace_set? && namespace
            return build_namespace_result(namespace, prefix)
          end

          # 2. Type-level namespace
          if attr && (type_ns_class = attr.type_namespace_class(register))
            return build_namespace_result(
              type_ns_class.uri,
              prefix || type_ns_class.prefix_default
            )
          end

          # 3. No namespace (W3C default for unprefixed attributes)
          { uri: nil, prefix: nil, ns_class: nil }
        end

        # Resolve namespace for XML elements
        #
        # Priority:
        # 1. Explicit namespace in mapping (highest)
        # 2. Type-level namespace
        # 3. Inherited namespace (namespace: :inherit)
        # 4. Form default qualification
        #
        # @param attr [Attribute] the attribute
        # @param register [Symbol, nil] register ID
        # @param parent_ns_uri [String, nil] parent namespace URI
        # @param parent_ns_class [Class, nil] parent namespace class
        # @param form_default [Symbol] :qualified or :unqualified
        # @return [Hash] namespace info
        def resolve_element_namespace(attr, register, parent_ns_uri,
                                     parent_ns_class, form_default)
          # 1. Explicit mapping namespace
          if namespace_set? && namespace != :inherit
            return build_namespace_result(namespace, prefix)
          end

          # 2. Type-level namespace
          if attr && (type_ns_class = attr.type_namespace_class(register))
            return build_namespace_result(
              type_ns_class.uri,
              prefix || type_ns_class.prefix_default
            )
          end

          # 3. Inherited namespace (explicit :inherit or form default)
          if namespace == :inherit ||
             (form_default == :qualified && parent_ns_uri)
            return build_namespace_result(parent_ns_uri, prefix)
          end

          # 4. No namespace (unqualified)
          { uri: nil, prefix: nil, ns_class: nil }
        end

        # Build namespace result hash
        #
        # @param uri [String, nil] namespace URI
        # @param prefix [String, nil] namespace prefix
        # @return [Hash] namespace info
        def build_namespace_result(uri, prefix)
          {
            uri: uri,
            prefix: prefix,
            ns_class: nil  # Could be enhanced if needed
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
