# frozen_string_literal: true

module Lutaml
  module Model
    module Lml
      # Reads a model class's declaration surfaces — the Attribute
      # registry and the TransformationRegistry-resolved per-format
      # mappings — and projects them into the neutral Document
      # (lutaml-model#1033 Phase 1).
      #
      # Only public introspection is used: `Klass.attributes(register)`,
      # `Klass.mappings_for(format, register)`, `Klass.mappings` (the
      # declared-format keys), `Lutaml::Model::Type`'s builtin registry.
      class Exporter
        SERIALIZABLE_BASE = Lutaml::Model::Serialize

        def self.export(klass, register: nil)
          new(klass, register: register).export
        end

        def initialize(klass, register: nil)
          @klass = klass
          # A nil caller register resolves through the model's own
          # declared default register (lutaml_default_register) — the
          # same precedence mappings_for applies internally, needed
          # explicitly here because attributes/type resolution takes
          # the register literally.
          @register = register ||
            (klass.lutaml_default_register if klass.respond_to?(:lutaml_default_register))
        end

        def export
          reject_non_serializable!
          reject_custom_initialize!
          Document.new(
            model_name: @klass.name,
            register: @register,
            attributes: @klass.attributes(@register).map { |_, attr| project_attribute(attr) },
            mappings: project_mappings,
          )
        end

        private

        def reject_non_serializable!
          return if @klass.is_a?(Class) && @klass.include?(SERIALIZABLE_BASE)

          raise RejectedError.new(:not_serializable, @klass,
                                  "the class does not include Lutaml::Model::Serializable")
        end

        # A custom `initialize` is constructor-contract: its body is not
        # a declaration. The exported document records nothing about it;
        # the model must be rejected so the schema stays honest.
        #
        # The framework prepends Serialize::Builder onto Serializable at
        # boot, so every plain model's initialize is owned by Builder.
        # The ownership check therefore walks the ancestry: the owner is
        # custom only when it sits between the model and its
        # Serializable boundary (the class itself or a module it
        # included).
        def reject_custom_initialize!
          owner = @klass.instance_method(:initialize).owner
          ancestors = @klass.ancestors
          boundary = ancestors.index(Lutaml::Model::Serializable)
          owner_index = owner && ancestors.index(owner)
          return if boundary.nil? || owner_index.nil? || owner_index >= boundary

          raise RejectedError.new(:custom_initialize, @klass,
                                  "initialize is owned by #{owner}; the body stays hand-written")
        end

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

        def type_name(attr)
          resolved =
            begin
              attr.type(@register)
            rescue UnknownTypeError
              # Deferred model references: consumers that declare
              # `attribute :x, "Ns::Model"` by string path resolve
              # through autoload, which the type resolver refuses to
              # materialize mid-finalization. Exporting happens
              # post-definition — materialize here.
              const_get_or_nil(attr.unresolved_type.to_s)
            end
          if resolved.nil?
            raise RejectedError.new(:unknown_type, @klass,
                                    "attribute #{attr.name} has an unresolved type")
          end

          builtin_name(resolved) || model_name_for(resolved, attr)
        end

        def const_get_or_nil(path)
          Object.const_get(path)
        rescue NameError
          nil
        end

        def builtin_name(resolved)
          builtin_registry.find { |_, klass| klass == resolved }&.first&.to_s
        end

        def builtin_registry
          @builtin_registry ||= begin
            registry = TypeRegistry.new
            Type.register_builtin_types_in(registry)
            registry.types
          end
        end

        def model_name_for(resolved, attr)
          return resolved.name if resolved.is_a?(Class) &&
            resolved.include?(SERIALIZABLE_BASE) && resolved.name

          raise RejectedError.new(:unknown_type, @klass,
                                  "attribute #{attr.name}: #{resolved} has no LML name")
        end

        def collection_field(attr)
          return nil unless attr.collection?

          range = attr.resolved_collection
          return true if range.nil?

          max = range.max
          max = nil if max.respond_to?(:infinite?) && max.infinite?
          { "min" => range.min, "max" => max }.compact
        end

        def static_default(attr)
          case attr.default_kind
          when :none
            nil
          when :static
            default = attr.options[:default]
            if default.is_a?(Float) && !default.finite?
              # JSON's canonical form cannot carry Infinity/NaN.
              raise RejectedError.new(:non_serializable_default, @klass,
                                      "attribute #{attr.name}: default #{default.inspect}")
            end
            default
          when :delegate
            raise RejectedError.new(:lambda_default, @klass,
                                    "attribute #{attr.name}: delegated defaults are not declarative")
          else # :proc
            raise RejectedError.new(:lambda_default, @klass,
                                    "attribute #{attr.name}: defaults must be constants in the schema")
          end
        end

        def reference_field(attr)
          ref = attr.options[:ref_model_class]
          return nil unless ref

          { "model" => class_path(ref) }.compact
        end

        def class_path(value)
          return nil if value.nil?
          return value.name if value.is_a?(Class)

          value.to_s
        end

        def true_or_nil(value)
          value ? true : nil
        end

        def project_mappings
          # Export per RESOLVED format, not per DSL block: the
          # key_value/rdf DSL fan one block out across the registered
          # formats, and each resolved format carries its own
          # projection.
          @klass.mappings.each_with_object({}) do |(format, _), out|
            out[format.to_s] = project_format(format)
          end
        end

        def project_format(format)
          mapping = @klass.mappings_for(format, @register)
          if mapping.respond_to?(:root_element)
            project_xml_mapping(mapping)
          else
            project_key_value_mapping(mapping)
          end
        end

        def project_xml_mapping(mapping)
          reject_imperative_element_order!(mapping)
          sequence = mapping.element_sequence
          sequence = nil if sequence.is_a?(Array) && sequence.empty?
          {
            "root" => root_field(mapping),
            "ordered" => true_or_nil(mapping.ordered?),
            "mixed_content" => true_or_nil(mapping.mixed_content?),
            "sequence" => sequence&.map(&:to_s),
            "namespace_uri" => mapping.namespace_uri,
            "namespace_prefix" => mapping.namespace_prefix,
            "rules" => mapping.mappings.map { |rule| project_xml_rule(rule) },
          }.compact
        end

        def reject_imperative_element_order!(mapping)
          sequence = mapping.element_sequence
          return if !mapping.ordered? || (sequence.is_a?(Array) && !sequence.empty?)

          raise RejectedError.new(:imperative_element_order, @klass,
                                  "ordered content without a declared sequence is instance-driven")
        end

        def root_field(mapping)
          return nil if mapping.root_element.nil?

          {
            "element" => mapping.root_element,
            "mixed" => true_or_nil(mapping.mixed_content?),
          }.compact
        end

        def project_xml_rule(rule)
          if rule.name.nil?
            # map_content: the content catch-all carries no name.
            return {
              "kind" => "content",
              "to" => rule.to&.to_s,
              "cdata" => true_or_nil(rule.cdata),
              "render_nil" => render_nil_field(rule),
            }.compact
          end

          {
            "kind" => rule.attribute ? "attribute" : "element",
            "name" => Array(rule.name).map(&:to_s),
            "to" => rule.to&.to_s,
            "namespace_uri" => xml_rule_namespace(rule),
            "prefix" => rule.prefix&.to_s,
            "cdata" => true_or_nil(rule.cdata),
            "render_nil" => render_nil_field(rule),
            "polymorphic_map" => polymorphic_map_field(rule),
          }.compact
        end

        def xml_rule_namespace(rule)
          namespace = rule.namespace
          return nil unless namespace.is_a?(String) || namespace.is_a?(Symbol)

          namespace.to_s
        end

        def render_nil_field(rule)
          value = rule.render_nil
          return nil unless value && value != false

          value == true ? true : value.to_s
        end

        def polymorphic_map_field(rule)
          return nil unless rule.polymorphic_map.is_a?(Hash) && rule.polymorphic_map.any?

          rule.polymorphic_map.to_h { |key, value| [class_path(key), value.to_s] }
        end

        def project_key_value_mapping(mapping)
          rules = mapping.mappings.map { |rule| project_key_value_rule(rule) }
          {
            "rules" => rules,
            "root_mappings" => root_mappings_field(mapping),
          }.compact
        end

        def root_mappings_field(mapping)
          return nil unless mapping.respond_to?(:root_mappings)

          root_mappings = mapping.root_mappings
          return nil unless root_mappings.is_a?(Hash) && root_mappings.any?

          root_mappings.to_h { |key, value| [key.to_s, value.to_s] }
        end

        def project_key_value_rule(rule)
          {
            "key" => Array(rule.name).map(&:to_s),
            "to" => rule.to&.to_s,
            "render_nil" => render_nil_field(rule),
            "child_mappings" => child_mappings_field(rule),
          }.compact
        end

        def child_mappings_field(rule)
          child_mappings = rule.child_mappings
          return nil unless child_mappings.is_a?(Hash) && child_mappings.any?

          child_mappings.to_h { |key, value| [key.to_s, canonicalize_value(value)] }
        end

        def canonicalize_value(value)
          case value
          when Hash then value.to_h { |key, item| [key.to_s, canonicalize_value(item)] }
          when Array then value.map { |item| canonicalize_value(item) }
          when Symbol then value.to_s
          else value
          end
        end
      end
    end
  end
end
