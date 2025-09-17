require_relative "../mapping/mapping_rule"

module Lutaml
  module Model
    module Xml
      class MappingRule < MappingRule
        attr_reader :namespace,
                    :prefix,
                    :mixed_content,
                    :default_namespace,
                    :cdata

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
          prefix_optional: false,
          mixed_content: false,
          cdata: false,
          namespace_set: false,
          prefix_set: false,
          attribute: false,
          default_namespace: nil,
          polymorphic: {},
          polymorphic_map: {},
          transform: {},
          value_map: {}
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
                         @ns_inherited = true
                         nil
                       else
                         @prefix_set = prefix_set
                         namespace
                       end
          @prefix = prefix
          @mixed_content = mixed_content
          @cdata = cdata

          @default_namespace = default_namespace

          @namespace_set = namespace_set
          @prefix_optional = prefix_optional
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

        def prefix_optional?
          !!@prefix_optional
        end

        def ns_inherited?
          !!@ns_inherited
        end

        def prefixable?
          ns_inherited? || prefix_set?
        end

        def prefixed_name
          rule_name = multiple_mappings? ? name.first : name
          if prefix
            "#{prefix}:#{rule_name}"
          else
            rule_name
          end
        end

        def namespaced_names(parent_namespace = nil, attr = nil, options = {})
          names = polymorphic_namespaced_names(attr, options)
          if multiple_mappings?
            name.each_with_object(names) do |rule_name, array|
              array << namespaced_name(parent_namespace, rule_name)
            end
          else
            names << namespaced_name(parent_namespace)
          end
          names << name.to_s if prefix_optional?
          names
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

        def update_default_namespace(uri)
          @default_namespace = uri
        end

        def update_prefix(new_prefix, optional: false)
          @prefix = new_prefix
          @prefix_optional = optional
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
          )
        end

        private

        def polymorphic_namespaced_names(attr, options)
          if !polymorphic&.empty? && polymorphic.key?(:class_map)
            polymorphic.dig(:class_map).values.each_with_object([]) do |mapping, array|
              array << [
                Object.const_get(mapping).mappings_for(:xml).namespace_uri,
                name,
              ].join(":")
            end
          else
            []
          end
        end
      end
    end
  end
end
