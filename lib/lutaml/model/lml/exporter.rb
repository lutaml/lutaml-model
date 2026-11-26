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
      #
      # This class holds what both document versions share (type
      # resolution, reject checks, the mapping walk); the version-specific
      # parts live in Exporter::V1Projector (the v1 Document) and
      # Exporter::V2Projector (the portable v2 Hash), which fill the
      # extension hooks below.
      class Exporter
        autoload :V1Projector, "#{__dir__}/exporter/v1_projector"
        autoload :V2Projector, "#{__dir__}/exporter/v2_projector"

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
        DEFAULT_NAMES = ->(klass) { klass.is_a?(::String) ? klass : klass.name }

        # The caller's explicit, trusted CONSTANTS for defaults the model
        # declares as code (a Proc or delegated default), indexed by stable
        # model ID and attribute name: {"Model@register" => {"attr" => value}}.
        # The exporter never calls such a default, reads its source or
        # changes it: a binding only supplies the declarative equivalent the
        # caller vouches for. A binding that targets a declared constant
        # default, an attribute with no default, or nothing at all is refused;
        # without a binding the default is still refused as lambda_default.
        class DefaultBindings
          MODEL_ID = /\A.+@[A-Za-z0-9_.:-]+\z/

          def self.wrap(source)
            return source if source.is_a?(self)

            new(source)
          end

          def initialize(entries)
            @entries = {}
            @used = {}
            raise invalid(entries, "default bindings must be a Hash of model id => {attribute => constant}") unless entries.nil? || entries.is_a?(::Hash)

            (entries || {}).each { |model_id, attributes| add(model_id.to_s, attributes) }
          end

          def key?(model_id, attribute)
            @entries.fetch(model_id, {}).key?(attribute)
          end

          # The bound constant; recorded as used.
          def value(model_id, attribute)
            @used[[model_id, attribute]] = true
            @entries.fetch(model_id).fetch(attribute)
          end

          # Every binding must have replaced an opaque default.
          def reject_unused!
            @entries.each do |model_id, attributes|
              attributes.each_key do |attribute|
                next if @used[[model_id, attribute]]

                raise invalid(model_id, "default binding #{attribute} matched no Proc or delegated default " \
                                        "of an exported model")
              end
            end
          end

          private

          def add(model_id, attributes)
            raise invalid(model_id, "default binding model id #{RejectedError.show(model_id)} must be Name@register") unless MODEL_ID.match?(model_id)
            raise invalid(model_id, "default bindings of #{model_id} are declared twice") if @entries.key?(model_id)
            unless attributes.is_a?(::Hash) && !attributes.empty?
              raise invalid(model_id, "default bindings of #{model_id} must be a non-empty Hash of attribute => constant")
            end

            @entries[model_id] = attributes.each_with_object({}) do |(name, constant), map|
              name = name.to_s
              raise invalid(model_id, "default binding attribute name #{RejectedError.show(name)} is empty") if name.empty?
              raise invalid(model_id, "default binding #{name} is declared twice") if map.key?(name)

              map[name] = constant
            end
          end

          def invalid(subject, detail)
            RejectedError.new(:invalid_document, subject, detail)
          end
        end

        # The caller's explicit, trusted FINITE case maps for polymorphic rules
        # whose class map is dynamic (a Hash with a default Proc that fills
        # itself on use, as Plurimath's Core::NODE_CLASS_MAP does). Indexed by
        # stable identity: {"Model@register" => {"format" => {"rule key" =>
        # {"wire value" => Class or "Class name"}}}}. The default Proc is
        # never called and no ObjectSpace scan guesses subclasses; an
        # unbound dynamic map is refused rather than exported empty.
        class PolymorphicBindings
          MODEL_ID = DefaultBindings::MODEL_ID

          def self.wrap(source)
            return source if source.is_a?(self)

            new(source)
          end

          def initialize(entries)
            @entries = {}
            @used = {}
            raise invalid(entries, "polymorphic bindings must be a Hash of model id => format => rule key => cases") unless entries.nil? || entries.is_a?(::Hash)

            (entries || {}).each { |model_id, formats| add_model(model_id.to_s, formats) }
          end

          def key?(model_id, format, rule_key)
            !lookup(model_id, format, rule_key).nil?
          end

          # The wire => target table, recorded as used.
          def cases(model_id, format, rule_key)
            found = lookup(model_id, format, rule_key)
            @used[found[:slot]] = true
            found[:cases]
          end

          def reject_unused!
            @entries.each do |model_id, formats|
              formats.each do |format, rules|
                rules.each_key do |key|
                  next if @used[[model_id, format, key]]

                  raise invalid(model_id, "polymorphic binding #{format}/#{key} matched no dynamic class map of an exported model")
                end
              end
            end
          end

          private

          # A derived format (hash, jsonl, yamls) reads its json/yaml twin.
          def lookup(model_id, format, rule_key)
            [format, *(DERIVED_FORMATS.include?(format) ? %w[json yaml] : [])].each do |candidate|
              cases = @entries.dig(model_id, candidate, rule_key)
              return { cases: cases, slot: [model_id, candidate, rule_key] } if cases
            end
            nil
          end

          def add_model(model_id, formats)
            raise invalid(model_id, "polymorphic binding model id #{RejectedError.show(model_id)} must be Name@register") unless MODEL_ID.match?(model_id)
            raise invalid(model_id, "polymorphic bindings of #{model_id} are declared twice") if @entries.key?(model_id)
            raise invalid(model_id, "bindings of #{model_id} must be a non-empty Hash of format => rules") unless formats.is_a?(::Hash) && !formats.empty?

            @entries[model_id] = formats.to_h do |format, rules|
              format = format.to_s
              raise invalid(model_id, "bindings of #{model_id}/#{format} must be a non-empty Hash of rule key => cases") unless rules.is_a?(::Hash) && !rules.empty?

              [format, rules.to_h { |key, table| [key.to_s, finite_cases(model_id, "#{format}/#{key}", table)] }]
            end
          end

          def finite_cases(model_id, label, table)
            raise invalid(model_id, "binding #{label} must be a non-empty Hash of wire value => class") unless table.is_a?(::Hash) && !table.empty?

            table.to_h do |wire, target|
              wire = wire.to_s
              raise invalid(model_id, "binding #{label}: wire value #{RejectedError.show(wire)} is empty") if wire.empty?
              unless target.is_a?(::Class) || (target.is_a?(::String) && !target.empty?)
                raise invalid(model_id, "binding #{label}: #{wire} must name a class")
              end

              [wire, target]
            end
          end

          def invalid(subject, detail)
            RejectedError.new(:invalid_document, subject, detail)
          end
        end

        def self.export(klass, register: nil, names: nil)
          V1Projector.new(klass, register: register, names: names).export
        end

        # Portable-v2 model document (lutaml-model#1033 contract in
        # 01-DOCUMENT-CONTRACT): tagged types, typed defaults, resolved
        # render policies, namespace modes and the ordered-content
        # descriptor. `export` keeps the v1 document unchanged.
        def self.project(klass, register: nil, names: nil, value_declarations: nil)
          V2Projector.new(klass, register: register, names: names, value_declarations: value_declarations).project
        end

        # The projector the graph exporter and the bundle gates call:
        # (klass, register string) -> v2 document Hash. "default" is the
        # absence of a register.
        #
        # +value_declarations+ is the caller-owned ValueDeclarations registry;
        # without it a custom value type is refused.
        #
        # +default_bindings+ supplies trusted constants for opaque defaults
        # (see DefaultBindings).
        # +polymorphic_bindings+ supplies trusted finite case maps for dynamic
        # polymorphic class maps (see PolymorphicBindings).
        def self.graph_projector(names: nil, value_declarations: nil, default_bindings: nil, polymorphic_bindings: nil)
          bindings = DefaultBindings.wrap(default_bindings)
          poly = PolymorphicBindings.wrap(polymorphic_bindings)
          lambda do |klass, register|
            V2Projector.new(klass, register: register.to_s == GraphExporter::DEFAULT_REGISTER ? nil : register.to_sym,
                                   names: names, value_declarations: value_declarations,
                                   default_bindings: bindings, polymorphic_bindings: poly).project
          end
        end

        # @param names [#call, nil] klass (or a class-name String, as a
        #   discriminator case may carry) -> the name the document records
        #   for that class (default: the class's own name). Lets a caller
        #   whose classes carry other names than the declarations they
        #   stand for (a materialized bundle) export in the original
        #   identifier space.
        def initialize(klass, register: nil, names: nil, value_declarations: nil, default_bindings: nil,
                       polymorphic_bindings: nil)
          unless value_declarations.nil? || value_declarations.is_a?(ValueDeclarations)
            raise ArgumentError, "value_declarations must be a ValueDeclarations registry"
          end

          @value_declarations = value_declarations
          @klass = klass
          @polymorphic_bindings = PolymorphicBindings.wrap(polymorphic_bindings)
          @default_bindings = DefaultBindings.wrap(default_bindings)
          @names = names || DEFAULT_NAMES
          # A nil caller register resolves through the model's own
          # declared default register (lutaml_default_register) — the
          # same precedence mappings_for applies internally, needed
          # explicitly here because attributes/type resolution takes
          # the register literally.
          @register = register ||
            (klass.lutaml_default_register if klass.respond_to?(:lutaml_default_register))
        end

        private

        # ---- extension hooks (version-specific) -------------------------

        def namespace_fields(_mapping) = raise(NotImplementedError)
        def content_rule_extras(_rule) = raise(NotImplementedError)
        def element_rule_extras(_rule) = raise(NotImplementedError)
        def key_value_rule_extras(_rule) = raise(NotImplementedError)
        def render_fields(_rule) = raise(NotImplementedError)
        def any_attribute_rule(_mapping) = nil
        def finish_mappings!(_projected) = nil
        def reject_executable_rule!(_rule, **) = nil
        def reject_custom_value_type!(_resolved, _attr) = nil

        # ---- naming ------------------------------------------------------

        def model_name(klass)
          @names.call(klass)
        end

        def portable_register
          name = (@register || "default").to_s
          return name if name.match?(PORTABLE_REGISTER)

          raise RejectedError.new(:invalid_document, @klass,
                                  "register #{RejectedError.show(name)} is not a portable name")
        end

        def model_id(klass)
          "#{model_name(klass)}@#{portable_register}"
        end

        def class_path(value)
          return nil if value.nil?
          return model_name(value) if value.is_a?(Class)

          value.to_s
        end

        # ---- reject checks ----------------------------------------------

        # The portable document addresses a model by its class path; an
        # anonymous class has none.
        def reject_anonymous!
          return unless @klass.respond_to?(:name) && (@klass.name.nil? || @klass.name.empty?)

          raise RejectedError.new(:invalid_document, @klass,
                                  "anonymous class has no portable model name")
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
          return unless custom_initialize?

          raise RejectedError.new(:custom_initialize, @klass,
                                  "initialize is hand-written (#{custom_initialize_source}); the body stays hand-written")
        end

        # True when the model carries application construction the document
        # cannot declare: a hand-written initialize owned by the class, a
        # module it includes or a parent class, or the marker a materialized
        # class carries (Lml::HandwrittenInitializer). Nothing is executed
        # and the body is never read.
        def custom_initialize?
          return true if materialized_marker?

          owner = custom_initialize_owner
          !owner.nil?
        end

        def materialized_marker?
          @klass.respond_to?(:lml_custom_initialize?) && @klass.lml_custom_initialize?
        end

        def custom_initialize_owner
          owner = @klass.instance_method(:initialize).owner
          ancestors = @klass.ancestors
          boundary = ancestors.index(Lutaml::Model::Serializable)
          owner_index = owner && ancestors.index(owner)
          return nil if boundary.nil? || owner_index.nil? || owner_index >= boundary

          owner
        end

        def custom_initialize_source
          materialized_marker? ? "marked by the bundle that materialized this class" : "owned by #{custom_initialize_owner}"
        end

        # ---- type resolution --------------------------------------------

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
          reject_custom_value_type!(resolved, attr)
          return model_name(resolved) if resolved.is_a?(Class) &&
            resolved.include?(SERIALIZABLE_BASE) && resolved.name

          raise RejectedError.new(:unknown_type, @klass,
                                  "attribute #{attr.name}: #{resolved} has no LML name")
        end

        # ---- attribute field helpers -------------------------------------

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
                                      "attribute #{attr.name}: default #{RejectedError.show(default)}")
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

        def true_or_nil(value)
          value ? true : nil
        end

        # ---- mappings -----------------------------------------------------

        def project_mappings
          # Export per RESOLVED format, not per DSL block: the
          # key_value/rdf DSL fan one block out across the registered
          # formats, and each resolved format carries its own
          # projection.
          projected = @klass.mappings.keys.to_h { |format| [format.to_s, project_format(format)] }
          finish_mappings!(projected)
          projected
        end

        def project_format(format)
          @format = format.to_s
          mapping = @klass.mappings_for(format, @register)
          if mapping.respond_to?(:root_element)
            project_xml_mapping(mapping)
          else
            project_key_value_mapping(mapping)
          end
        end

        def project_xml_mapping(mapping)
          @xml_mapping = mapping
          reject_imperative_element_order!(mapping)
          {
            "root" => root_field(mapping),
            "ordered" => true_or_nil(mapping.ordered?),
            "mixed_content" => true_or_nil(mapping.mixed_content?),
            "sequence" => sequence_field(mapping),
            "rules" => project_xml_rules(mapping),
          }.merge(namespace_fields(mapping)).compact
        end

        # The explicit rules in declared order, then the catch-all
        # attribute rule (Ruby emits that remainder after the mapped
        # attributes, so it is the last rule).
        def project_xml_rules(mapping)
          rules = mapping.mappings.map { |rule| project_xml_rule(rule) }
          any = any_attribute_rule(mapping)
          rules << any if any
          rules
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
            }.merge(content_rule_extras(rule)).merge(render_fields(rule)).compact
          end

          reject_executable_rule!(rule)
          {
            "kind" => rule.attribute ? "attribute" : "element",
            "name" => Array(rule.name).map(&:to_s),
            "to" => rule.to&.to_s,
            "cdata" => true_or_nil(rule.cdata),
            "polymorphic_map" => polymorphic_map_field(rule),
          }.merge(element_rule_extras(rule)).merge(render_fields(rule)).compact
        end

        def render_policy_field(value)
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
          reject_executable_rule!(rule, key_value: true)
          {
            "key" => Array(rule.name).map(&:to_s),
            "to" => rule.to&.to_s,
            "child_mappings" => child_mappings_field(rule),
          }.merge(key_value_rule_extras(rule)).merge(render_fields(rule)).compact
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
