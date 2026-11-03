# frozen_string_literal: true

require "bigdecimal"
require "date"
require "time"

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
        ORDERED_CONTENT_MEMBER = "__lml_content"
        ORDERED_CONTENT = { "member" => ORDERED_CONTENT_MEMBER, "version" => 1 }.freeze
        PORTABLE_REGISTER = /\A[A-Za-z0-9_.:-]+\z/
        RENDER_NAMES = { omitted: "omit", nil: "as_nil", empty: "as_empty",
                         blank: "as_blank" }.freeze
        # key_value/rdf DSL blocks fan out to these resolved formats that
        # are not wire formats of the v2 contract (in-memory Hash,
        # line-delimited json/yaml). Portable output omits one only when
        # it is identical to the json/yaml projection, else refuses it.
        DERIVED_FORMATS = %w[hash jsonl yamls].freeze
        # Attribute options the portable document carries (the rest of
        # the option space is behaviour — transforms, patterns, facets,
        # polymorphism, choices, references — with no slot in the v2
        # contract, so a model using one is refused by name instead of
        # exporting a plain attribute that silently loses it).
        PORTABLE_ATTRIBUTE_OPTIONS = %i[default collection values initialize_empty
                                        required desc].freeze
        REFERENCE_OPTIONS = %i[ref_model_class ref_key_attribute].freeze
        INTEGER_TYPES = %w[integer].freeze
        BOOLEAN_TYPES = %w[boolean].freeze
        STRING_TYPES = %w[string token uri email hostname ip decimal rational date time
                          date_time time_without_date duration qname base64_binary
                          hex_binary symbol].freeze

        def self.export(klass, register: nil)
          new(klass, register: register).export
        end

        # Portable-v2 model document (lutaml-model#1033 contract in
        # 01-DOCUMENT-CONTRACT): tagged types, typed defaults, resolved
        # render policies, namespace modes and the ordered-content
        # descriptor. `export` keeps the v1 document unchanged.
        def self.project(klass, register: nil)
          new(klass, register: register, portable: true).project
        end

        def initialize(klass, register: nil, portable: false)
          @klass = klass
          @portable = portable
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
          reject_reserved_member!
          Document.new(
            model_name: @klass.name,
            register: @register,
            attributes: @klass.attributes(@register).map { |_, attr| project_attribute(attr) },
            mappings: project_mappings,
          )
        end

        def project
          reject_non_serializable!
          reject_anonymous!
          reject_custom_initialize!
          reject_reserved_member!
          mappings = project_mappings
          {
            "lml" => 2,
            "model" => @klass.name,
            "register" => portable_register,
            "attributes" => @klass.attributes(@register).map { |_, attr| project_attribute(attr) },
            "mappings" => mappings,
            "ordered_content" => ordered_content_descriptor,
          }.compact
        end

        private

        def portable_register
          name = (@register || "default").to_s
          return name if name.match?(PORTABLE_REGISTER)

          raise RejectedError.new(:invalid_document, @klass,
                                  "register #{name.inspect} is not a portable name")
        end

        # The portable document addresses a model by its class path; an
        # anonymous class has none.
        def reject_anonymous!
          return unless @klass.respond_to?(:name) && (@klass.name.nil? || @klass.name.empty?)

          raise RejectedError.new(:invalid_document, @klass,
                                  "anonymous class has no portable model name")
        end

        def model_id(klass)
          "#{klass.name}@#{portable_register}"
        end

        def reject_reserved_member!
          return unless @klass.attributes(@register).key?(ORDERED_CONTENT_MEMBER.to_sym)

          raise RejectedError.new(:reserved_member, @klass,
                                  "#{ORDERED_CONTENT_MEMBER} is reserved for ordered content")
        end

        def ordered_content_descriptor
          return nil unless ordered_models?

          ORDERED_CONTENT
        end

        def ordered_models?
          @klass.mappings.keys.any? do |format|
            mapping = @klass.mappings_for(format, @register)
            mapping.respond_to?(:ordered?) && (mapping.ordered? || mapping.mixed_content?)
          end
        end

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
          return project_portable_attribute(attr) if @portable

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

        def project_portable_attribute(attr)
          reject_unportable_options!(attr)
          {
            "name" => attr.name.to_s,
            "type" => portable_type(attr),
            "required" => attr.options[:required] ? true : false,
            "collection" => portable_collection(attr),
            "default" => portable_default(attr),
            "initialize_empty" => attr.initialize_empty? == true,
            "values" => portable_enum(attr),
            "reference" => reference_field(attr),
          }.compact
        end

        def reject_unportable_options!(attr)
          attr.options.each do |key, value|
            next if PORTABLE_ATTRIBUTE_OPTIONS.include?(key)
            next if value.nil? || value.equal?(false) || empty_option?(value)
            next if declarative_option?(key, value)

            reason = REFERENCE_OPTIONS.include?(key) ? :unsupported_type : :unsupported_mapping
            raise RejectedError.new(reason, @klass,
                                    "attribute #{attr.name}: option #{key} has no portable form")
          end
        end

        def empty_option?(value)
          value.respond_to?(:empty?) && value.empty?
        end

        # Carried by the mapping contract, not the attribute: the XML
        # `sequence { choice {} }` compositor (its bounds travel in the
        # mapping's choice member) and the polymorphic_class marker (the
        # rule's polymorphic_map). A model-level `choice {}` block is
        # validation behaviour with no portable slot.
        def declarative_option?(key, value)
          return @klass.choice_attributes.none? { |c| c.equal?(value) } if key == :choice

          key == :polymorphic_class
        end

        def portable_type(attr)
          name = type_name(attr)
          resolved = resolve_type(attr)
          return { "kind" => "model", "id" => model_id(resolved) } if name == resolved&.name

          { "kind" => "builtin", "name" => name }
        end

        def portable_collection(attr)
          return custom_collection(attr) if attr.options[:collection].is_a?(Class)

          field = collection_field(attr)
          return false if field.nil?
          return { "min" => 0, "max" => nil } if field == true

          { "min" => field["min"], "max" => field["max"] }
        end

        # A custom collection class travels by name (an importer supplies
        # the trusted binding); an unnameable one has no portable form.
        def custom_collection(attr)
          name = attr.options[:collection].name
          if name.nil? || name.empty?
            raise RejectedError.new(:unsupported_mapping, @klass,
                                    "attribute #{attr.name}: an anonymous collection class has no portable name")
          end

          { "min" => 0, "max" => nil, "class" => name }
        end

        def float_attribute?(attr)
          type_name(attr) == "float"
        end

        def portable_default(attr)
          return { "present" => false } if attr.default_kind == :none

          { "present" => true, "value" => portable_value(attr, static_default(attr), "default") }
        end

        def portable_enum(attr)
          values = attr.enum_values
          return nil if values.nil? || values.empty?

          values.to_a.map { |value| portable_value(attr, value, "values") }
        end

        # A default or enum value as the JSON scalar (or array/object of
        # scalars) the declared type can express; anything else is refused
        # at export rather than failing the bundle later.
        def portable_value(attr, value, what)
          kind = portable_kind(attr)
          if attr.collection? && what == "default" && value.is_a?(::Array)
            return value.map { |item| portable_scalar(attr, kind, item, what) }
          end

          portable_scalar(attr, kind, value, what)
        end

        def portable_kind(attr)
          resolve_type(attr).nil? ? nil : type_name(attr)
        end

        def portable_scalar(attr, kind, value, what)
          json = json_value(attr, value, what)
          return json if json.nil?

          ok = if kind == "float" then json.is_a?(::Numeric)
               elsif INTEGER_TYPES.include?(kind) then json.is_a?(::Integer)
               elsif BOOLEAN_TYPES.include?(kind) then [true, false].include?(json)
               elsif STRING_TYPES.include?(kind) then json.is_a?(::String)
               elsif kind == "hash" then json.is_a?(::Hash)
               else true
               end
          unless ok
            raise RejectedError.new(:non_serializable_default, @klass,
                                    "attribute #{attr.name}: #{what} #{value.inspect} is not a #{kind}")
          end

          kind == "float" ? DocumentValidator.float_wire(json) : json
        end

        def json_value(attr, value, what)
          case value
          when nil, true, false, ::Integer, ::String then value
          when ::Symbol then value.to_s
          when ::Float
            return value if value.finite?

            refuse_value(attr, value, what)
          when ::Date, ::Time then value.iso8601
          when ::BigDecimal then value.to_s("F")
          when ::Rational then value.to_s
          when ::Array then value.map { |item| json_value(attr, item, what) }
          when ::Hash then value.to_h { |k, v| [k.to_s, json_value(attr, v, what)] }
          else refuse_value(attr, value, what)
          end
        end

        def refuse_value(attr, value, what)
          raise RejectedError.new(:non_serializable_default, @klass,
                                  "attribute #{attr.name}: #{what} #{value.inspect} has no JSON form")
        end

        def enum_field(attr)
          values = attr.enum_values
          return nil if values.nil? || values.empty?

          values.map(&:to_s)
        end

        def type_name(attr)
          resolved = resolve_type(attr)
          if resolved.nil?
            raise RejectedError.new(:unknown_type, @klass,
                                    "attribute #{attr.name} has an unresolved type")
          end

          builtin_name(resolved) || model_name_for(resolved, attr)
        end

        def resolve_type(attr)
          attr.type(@register)
        rescue UnknownTypeError
          # Deferred model references: consumers that declare
          # `attribute :x, "Ns::Model"` by string path resolve
          # through autoload, which the type resolver refuses to
          # materialize mid-finalization. Exporting happens
          # post-definition — materialize here.
          const_get_or_nil(attr.unresolved_type.to_s)
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
          if @portable && resolved.is_a?(Class) && resolved <= Lutaml::Model::Type::Value && resolved.name
            # The exporter emits no bundle value_types, so a custom value
            # type could never pass the gate; refuse it by name.
            raise RejectedError.new(:unsupported_type, @klass,
                                    "attribute #{attr.name}: custom value type #{resolved.name} has no portable form")
          end
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
          projected = @klass.mappings.keys.to_h { |format| [format.to_s, project_format(format)] }
          return projected unless @portable

          DERIVED_FORMATS.each { |format| drop_derived_format!(projected, format) }
          projected
        end

        def drop_derived_format!(projected, format)
          return unless projected.key?(format)

          twin = projected["json"] || projected["yaml"]
          unless twin && projected[format] == twin
            raise RejectedError.new(:unsupported_mapping, @klass,
                                    "format #{format} has no portable form")
          end
          projected.delete(format)
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
          base = {
            "root" => root_field(mapping),
            "ordered" => true_or_nil(mapping.ordered?),
            "mixed_content" => true_or_nil(mapping.mixed_content?),
            "sequence" => sequence_field(mapping),
            "rules" => mapping.mappings.map { |rule| project_xml_rule(rule) },
          }
          if @portable
            base["namespace"] = mapping_namespace(mapping)
          else
            base["namespace_uri"] = mapping.namespace_uri
            base["namespace_prefix"] = mapping.namespace_prefix
            base["ordered_content"] = ORDERED_CONTENT if mapping.ordered? || mapping.mixed_content?
          end
          base.compact
        end

        # Both v1 and v2 project every sequence compositor as
        # {kind:"sequence", members:[...]}: member element rules in
        # declared order, with a nested choice as
        # {kind:"choice",min,max,members:[...]} at the position of its
        # first member. (v1 formerly emitted Sequence#to_s, which embeds
        # an object address and made exports differ between runs.)
        def sequence_field(mapping)
          sequences = mapping.element_sequence
          return nil unless sequences.is_a?(Array) && sequences.any?

          sequences.map { |sequence| project_sequence(sequence) }
        end

        def project_sequence(sequence)
          members = []
          placed = []
          sequence.attributes.each do |rule|
            choice = sequence.compositors.find { |c| c.attributes.any? { |a| a.name == rule.to } }
            if choice.nil?
              members << project_xml_rule(rule)
            elsif !placed.include?(choice)
              placed << choice
              members << project_choice(choice, sequence)
            end
          end
          { "kind" => "sequence", "members" => members }
        end

        def project_choice(choice, sequence)
          names = choice.attributes.map(&:name)
          rules = sequence.attributes.select { |rule| names.include?(rule.to) }
          { "kind" => "choice", "min" => choice.min, "max" => choice.max,
            "members" => rules.map { |rule| project_xml_rule(rule) } }
        end

        def mapping_namespace(mapping)
          return { "mode" => "inherit" } if mapping.namespace_uri.nil?

          { "mode" => "uri", "uri" => mapping.namespace_uri,
            "prefix" => mapping.namespace_prefix }.compact
        end

        # Declarative ordered/mixed content exports (per-instance order is
        # data, carried by the ordered-content descriptor). Only order
        # driven by executable callbacks has no declarative form.
        def reject_imperative_element_order!(mapping)
          return unless mapping.ordered? || mapping.mixed_content?

          callback = mapping.mappings.find { |rule| rule.custom_methods.to_h.any? }
          callback ||= mapping.all_listeners.first if mapping.respond_to?(:all_listeners)
          return unless callback

          raise RejectedError.new(:imperative_element_order, @klass,
                                  "ordered content is driven by an executable callback")
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
              "render_nil" => (render_nil_field(rule) unless @portable),
            }.merge(render_fields(rule)).compact
          end

          reject_executable_rule!(rule)
          {
            "kind" => rule.attribute ? "attribute" : "element",
            "name" => Array(rule.name).map(&:to_s),
            "to" => rule.to&.to_s,
            "namespace_uri" => (xml_rule_namespace(rule) unless @portable),
            "prefix" => (rule.prefix&.to_s unless @portable),
            "cdata" => true_or_nil(rule.cdata),
            "render_nil" => (render_nil_field(rule) unless @portable),
            "polymorphic_map" => polymorphic_map_field(rule),
            "discriminator" => discriminator_field(rule),
          }.merge(render_fields(rule)).compact
        end

        # Executable rule parts have no portable form; refuse without
        # calling them.
        def reject_executable_rule!(rule)
          return unless @portable

          if rule.custom_methods.to_h.any?
            raise RejectedError.new(:unsupported_mapping, @klass,
                                    "rule #{Array(rule.name).first}: custom with: methods are executable")
          end
          return if rule.transform.to_h.empty?

          raise RejectedError.new(:unsupported_mapping, @klass,
                                  "rule #{Array(rule.name).first}: transform is executable")
        end

        def discriminator_field(rule)
          return nil unless @portable

          poly = rule.polymorphic
          return nil unless poly.is_a?(::Hash) && poly[:attribute]

          cases = (poly[:class_map] || {}).to_h do |wire, target|
            [wire.to_s, target.is_a?(Class) ? model_id(target) : "#{target}@#{portable_register}"]
          end
          { "attribute" => poly[:attribute].to_s, "cases" => cases }
        end

        # v1: render_empty / render_default / value_map when they depart
        # from the defaults. v2: one resolved "render" object.
        def render_fields(rule)
          if @portable
            return { "render" => resolved_render(rule),
                     "namespace" => (rule_namespace(rule) if rule.respond_to?(:namespace_param) && rule.name) }
          end

          {
            "render_empty" => render_policy_field(rule.render_empty),
            "render_default" => true_or_nil(rule.render_default),
            "value_map" => value_map_field(rule),
          }
        end

        def rule_namespace(rule)
          return { "mode" => "inherit" } if rule.namespace_param.nil? || rule.namespace_param == :inherit
          return { "mode" => "unqualified" } if rule.namespace_param == :blank || rule.namespace.nil?

          { "mode" => "uri", "uri" => rule.namespace, "prefix" => rule.prefix&.to_s }.compact
        end

        def render_policy_field(value)
          return nil unless value && value != false

          value == true ? true : value.to_s
        end

        def value_map_field(rule)
          defaults = rule.default_value_map
          actual = { from: rule.value_map(:from), to: rule.value_map(:to) }
          return nil if actual == defaults

          actual.to_h do |dir, map|
            [dir.to_s, map.to_h { |key, value| [key.to_s, value.to_s] }]
          end
        end

        def resolved_render(rule)
          to = rule.value_map(:to)
          {
            "nil" => RENDER_NAMES.fetch(to[:nil]),
            "empty" => RENDER_NAMES.fetch(to[:empty]),
            "default" => rule.render_default ? true : false,
          }
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
          return nil unless rule.polymorphic_map.is_a?(::Hash) && rule.polymorphic_map.any?

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
          return nil unless root_mappings.is_a?(::Hash) && root_mappings.any?

          root_mappings.to_h { |key, value| [key.to_s, value.to_s] }
        end

        def project_key_value_rule(rule)
          reject_executable_rule!(rule)
          {
            "key" => Array(rule.name).map(&:to_s),
            "to" => rule.to&.to_s,
            "render_nil" => (render_nil_field(rule) unless @portable),
            "child_mappings" => child_mappings_field(rule),
            "root_mappings" => rule_root_mappings_field(rule),
            "discriminator" => discriminator_field(rule),
          }.merge(render_fields(rule)).compact
        end

        def rule_root_mappings_field(rule)
          return nil unless @portable

          root_mappings = rule.respond_to?(:root_mappings) ? rule.root_mappings : nil
          return nil unless root_mappings.is_a?(::Hash) && root_mappings.any?

          root_mappings.to_h { |key, value| [key.to_s, canonicalize_value(value)] }
        end

        def child_mappings_field(rule)
          child_mappings = rule.child_mappings
          return nil unless child_mappings.is_a?(::Hash) && child_mappings.any?

          child_mappings.to_h { |key, value| [key.to_s, canonicalize_value(value)] }
        end

        def canonicalize_value(value)
          case value
          when ::Hash then value.to_h { |key, item| [key.to_s, canonicalize_value(item)] }
          when Array then value.map { |item| canonicalize_value(item) }
          when Symbol then value.to_s
          else value
          end
        end
      end
    end
  end
end
