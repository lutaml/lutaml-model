# frozen_string_literal: true

module Lutaml
  module Model
    module Lml
      class Exporter
        # The v1 document: a Lml::Document with the original attribute and
        # mapping vocabulary (unresolved render policies, XML namespace
        # strings, per-mapping ordered-content marker). Frozen — any change
        # moves the v1 checksum.
        class V1Projector < Exporter
          def export
            reject_non_serializable!
            reject_custom_initialize!
            reject_reserved_member!
            Document.new(
              model_name: model_name(@klass),
              register: @register,
              attributes: @klass.attributes(@register).map { |_, attr| project_attribute(attr) },
              mappings: project_mappings,
            )
          end

          private

          def project_attribute(attr)
            {
              "name" => attr.name.to_s,
              "type" => type_name(attr),
              "collection" => collection_field(attr),
              "default" => static_default(attr),
              "required" => true_or_nil(attr.options[:required]),
              "values" => enum_field(attr),
              "initialize_empty" => true_or_nil(attr.initialize_empty?),
              "polymorphic_class" => class_path(attr.options[:polymorphic_class]),
              "reference" => reference_field(attr),
            }.compact
          end

          def enum_field(attr)
            values = attr.enum_values
            return nil if values.nil? || values.empty?

            values.map(&:to_s)
          end

          def namespace_fields(mapping)
            fields = { "namespace_uri" => mapping.namespace_uri,
                       "namespace_prefix" => mapping.namespace_prefix }
            fields["ordered_content"] = ORDERED_CONTENT if mapping.ordered? || mapping.mixed_content?
            fields
          end

          def content_rule_extras(rule)
            { "render_nil" => render_nil_field(rule) }
          end

          def element_rule_extras(rule)
            { "namespace_uri" => xml_rule_namespace(rule),
              "prefix" => rule.prefix&.to_s,
              "render_nil" => render_nil_field(rule) }
          end

          def key_value_rule_extras(rule)
            { "render_nil" => render_nil_field(rule) }
          end

          # render_empty / render_default / value_map when they depart
          # from the defaults.
          def render_fields(rule)
            {
              "render_empty" => render_policy_field(rule.render_empty),
              "render_default" => true_or_nil(rule.render_default),
              "value_map" => value_map_field(rule),
            }
          end

          def render_nil_field(rule)
            render_policy_field(rule.render_nil)
          end

          def value_map_field(rule)
            defaults = rule.default_value_map
            actual = { from: rule.value_map(:from), to: rule.value_map(:to) }
            return nil if actual == defaults

            actual.to_h do |dir, map|
              [dir.to_s, map.to_h { |key, value| [key.to_s, value.to_s] }]
            end
          end

          def xml_rule_namespace(rule)
            namespace = rule.namespace
            return nil unless namespace.is_a?(String) || namespace.is_a?(Symbol)

            namespace.to_s
          end
        end
      end
    end
  end
end
