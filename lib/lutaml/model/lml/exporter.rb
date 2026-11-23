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

        # The caller's explicit, trusted declaration of the custom value
        # types an export may name (lutaml-model#1033): value type ID =>
        # {class:, base:, facets:}. The exporter never infers a type's
        # behaviour from its Ruby class, so a custom type is exported only
        # when the caller states its stable ID, its source class, the
        # builtin it is based on and the facets it carries; the result is
        # the bundle's existing `value_types[id] = {base, facets}`
        # declaration plus `{kind:"value", id:}` attribute types.
        #
        # Matching is by class identity: a subclass of a registered class is
        # a different, unregistered type. Registering a builtin type class,
        # one class under two IDs, an unnamed class or an invalid
        # declaration is refused here, before any model is exported.
        class ValueTypeRegistry
          ID_FORMAT = /\A[A-Za-z0-9_.:-]+\z/
          ENTRY_KEYS = %i[class base facets].freeze
          COUNT_FACETS = %w[length min_length max_length total_digits fraction_digits].freeze
          TEXT_FACETS = %w[pattern white_space].freeze
          WHITE_SPACE = %w[preserve replace collapse].freeze
          BOUND_FACETS = %w[min_inclusive max_inclusive min_exclusive max_exclusive].freeze
          NUMERIC_BASES = %w[integer decimal positive_integer non_negative_integer].freeze
          DECIMAL_TEXT = /\A-?\d+(?:\.\d+)?\z/
          ORDERED_FACETS = [%w[min_length max_length], %w[fraction_digits total_digits]].freeze

          # @param source [ValueTypeRegistry, Hash, nil]
          # @return [ValueTypeRegistry]
          def self.wrap(source)
            return source if source.is_a?(self)

            new(source)
          end

          def initialize(entries)
            @by_id = {}
            @by_class = {}
            raise reject(entries, "value types must be a Hash of id => declaration") unless entries.nil? || entries.is_a?(::Hash)

            (entries || {}).each { |id, entry| register(id.to_s, entry) }
            @by_id.freeze
            @by_class.freeze
          end

          def empty?
            @by_id.empty?
          end

          # @return [String, nil] the registered ID for exactly +klass+
          def id_for(klass)
            @by_class[klass]
          end

          # The bundle-level declaration of a registered ID.
          def definition(id)
            @by_id.fetch(id)[:definition]
          end

          # Why +json+ (a default already shaped for the base) violates a
          # facet of +id+, or nil. Bounds and digit counts apply to numeric
          # bases, compared as exact decimal text; length and pattern to
          # the other (string-shaped) bases.
          def facet_violation(id, json)
            definition = @by_id.fetch(id)[:definition]
            base = definition["base"]
            definition["facets"].each do |name, limit|
              problem = if NUMERIC_BASES.include?(base) then numeric_problem(name, limit, json)
                        elsif base == "float" && BOUND_FACETS.include?(name) then float_bound_problem(name, limit, json)
                        else text_problem(name, limit, json)
                        end
              return problem if problem
            end
            nil
          end

          # The builtin a registered ID's values are written as.
          def base(id)
            @by_id.fetch(id)[:definition]["base"]
          end

          private

          def text_problem(name, limit, json)
            return nil unless json.is_a?(::String)

            case name
            when "length", "min_length", "max_length"
              size = json.length
              ok = { "length" => size == limit, "min_length" => size >= limit, "max_length" => size <= limit }[name]
              ok ? nil : "length #{size} breaks #{name} #{limit}"
            when "pattern"
              Regexp.new("\\A(?:#{limit})\\z").match?(json) ? nil : "#{RejectedError.show(json)} does not match pattern #{limit}"
            end
          end

          def numeric_problem(name, limit, json)
            text = json.to_s
            return nil unless json.is_a?(::Integer) || (json.is_a?(::String) && DECIMAL_TEXT.match?(json))

            if BOUND_FACETS.include?(name)
              bound_problem(name, limit, text)
            elsif %w[total_digits fraction_digits].include?(name)
              digit_problem(name, limit, text)
            end
          end

          # A canonical float default is its wire string (`2.0`, `1.0e-5`);
          # BigDecimal reads that text exactly, so the bound is compared with
          # no Float intermediate. Digit counts have no float meaning.
          def float_bound_problem(name, limit, json)
            return nil unless json.is_a?(::String) && DocumentValidator::FLOAT_WIRE.match?(json)

            bound_problem(name, limit, json)
          end

          def bound_problem(name, limit, text)
            value = BigDecimal(text)
            edge = BigDecimal(limit.to_s)
            ok = { "min_inclusive" => value >= edge, "max_inclusive" => value <= edge,
                   "min_exclusive" => value > edge, "max_exclusive" => value < edge }[name]
            ok ? nil : "#{text} breaks #{name} #{limit}"
          end

          # XSD digit counts on the exact decimal text: the sign, leading
          # zeros and trailing fraction zeros are not digits; zero counts as
          # one total digit (as the Rust loader does).
          def digit_problem(name, limit, text)
            whole, fraction = text.delete("-").split(".", 2)
            fraction = fraction.to_s.sub(/0+\z/, "")
            total = (whole + fraction).sub(/\A0+/, "").length.clamp(1..)
            count = name == "total_digits" ? total : fraction.length
            count <= limit ? nil : "#{text} has #{count} digits, breaking #{name} #{limit}"
          end

          def register(id, entry)
            raise reject(id, "value type id #{RejectedError.show(id)} must match #{ID_FORMAT.source}") unless ID_FORMAT.match?(id)
            raise reject(id, "value type #{id} is declared twice") if @by_id.key?(id)
            raise reject(id, "value type #{id} must be a Hash with #{ENTRY_KEYS.join(', ')}") unless entry.is_a?(::Hash)

            entry = entry.transform_keys(&:to_sym)
            unknown = entry.keys - ENTRY_KEYS
            raise reject(id, "value type #{id}: unknown key #{unknown.first.inspect}") if unknown.any?

            klass = source_class(id, entry[:class])
            if (owner = @by_class[klass])
              raise reject(id, "#{klass} is registered as both #{owner} and #{id}; the binding is ambiguous")
            end

            definition = { "base" => base_name(id, entry[:base]), "facets" => facets(id, entry[:facets] || {}) }
            @by_id[id] = { klass: klass, definition: definition }
            @by_class[klass] = id
          end

          def source_class(id, klass)
            unless klass.is_a?(::Class) && klass <= Lutaml::Model::Type::Value
              raise reject(id, "value type #{id}: class must be a Lutaml::Model::Type::Value class")
            end
            raise reject(id, "value type #{id}: an unnamed class has no stable source name") if klass.name.to_s.empty?
            if builtin_classes.include?(klass)
              raise reject(id, "value type #{id}: #{klass} is a builtin type; it is not a custom value type")
            end

            klass
          end

          def base_name(id, base)
            base = base.to_s
            return base if DocumentValidator::BUILTIN_TYPES.include?(base)

            reason = DocumentValidator::UNSUPPORTED_BUILTINS.include?(base) ? :unsupported_type : :unknown_type
            raise RejectedError.new(reason, id, "value type #{id}: base #{RejectedError.show(base)} is not a builtin")
          end

          def facets(id, facets)
            raise reject(id, "value type #{id}: facets must be a Hash") unless facets.is_a?(::Hash)

            checked = facets.to_h { |name, value| [name.to_s, facet_value(id, name.to_s, value)] }
            ORDERED_FACETS.each do |low, high|
              next unless checked.key?(low) && checked.key?(high) && checked[low] > checked[high]

              raise reject(id, "value type #{id}: #{low} exceeds #{high}")
            end
            checked
          end

          def facet_value(id, name, value)
            if COUNT_FACETS.include?(name)
              return value if safe_integer?(value) && value >= 0
            elsif name == "pattern"
              return value if value.is_a?(::String) && !value.empty? && DocumentValidator.portable_string?(value) &&
                compiles?(value)
            elsif name == "white_space"
              return value if WHITE_SPACE.include?(value)
            elsif BOUND_FACETS.include?(name)
              return value if safe_integer?(value) || (value.is_a?(::String) && DECIMAL_TEXT.match?(value))
            else
              raise RejectedError.new(:unsupported_type, id, "value type #{id}: unsupported facet #{RejectedError.show(name)}")
            end
            raise reject(id, "value type #{id}: facet #{name} has an invalid value #{RejectedError.show(value)}")
          end

          def compiles?(pattern)
            Regexp.new(pattern)
            true
          rescue RegexpError
            false
          end

          def safe_integer?(value)
            value.is_a?(::Integer) && value.abs <= DocumentValidator::MAX_SAFE_INTEGER
          end

          def reject(subject, detail)
            RejectedError.new(:invalid_document, subject, detail)
          end

          def builtin_classes
            @builtin_classes ||= begin
              registry = TypeRegistry.new
              Type.register_builtin_types_in(registry)
              registry.types.values
            end
          end
        end

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

        def self.export(klass, register: nil, names: nil)
          V1Projector.new(klass, register: register, names: names).export
        end

        # Portable-v2 model document (lutaml-model#1033 contract in
        # 01-DOCUMENT-CONTRACT): tagged types, typed defaults, resolved
        # render policies, namespace modes and the ordered-content
        # descriptor. `export` keeps the v1 document unchanged.
        def self.project(klass, register: nil, names: nil)
          V2Projector.new(klass, register: register, names: names).project
        end

        # The projector the graph exporter and the bundle gates call:
        # (klass, register string) -> v2 document Hash. "default" is the
        # absence of a register.
        #
        # +value_types+ is the explicit custom value type registry (a Hash
        # of id => {class:, base:, facets:}); without it a custom value type
        # is refused. Registered types travel as a per-model "value_types"
        # entry that only the graph exporter reads: it hoists them into the
        # bundle, the one place the wire contract carries them. A
        # standalone document therefore never accepts a registry.
        #
        # +default_bindings+ supplies trusted constants for opaque defaults
        # (see DefaultBindings).
        def self.graph_projector(names: nil, value_types: nil, default_bindings: nil)
          registry = ValueTypeRegistry.wrap(value_types)
          bindings = DefaultBindings.wrap(default_bindings)
          lambda do |klass, register|
            V2Projector.new(klass, register: register.to_s == GraphExporter::DEFAULT_REGISTER ? nil : register.to_sym,
                                   names: names, value_types: registry, default_bindings: bindings).project
          end
        end

        # @param names [#call, nil] klass (or a class-name String, as a
        #   discriminator case may carry) -> the name the document records
        #   for that class (default: the class's own name). Lets a caller
        #   whose classes carry other names than the declarations they
        #   stand for (a materialized bundle) export in the original
        #   identifier space.
        def initialize(klass, register: nil, names: nil, value_types: nil, default_bindings: nil)
          @klass = klass
          @value_types = ValueTypeRegistry.wrap(value_types)
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
        def reject_executable_rule!(_rule) = nil
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
          reject_executable_rule!(rule)
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
