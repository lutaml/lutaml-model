# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      # Functional xsd:union: an attribute value conforms to one of several
      # declared member types. A single shared class recognized by identity
      # (mirrors Type::Reference); the per-attribute member list lives in the
      # attribute's @options[:union_member_types]. Stateless: serialization is
      # driven by value.class, never by per-instance tracking.
      #
      # This class owns ALL union knowledge: the conformance engine, the
      # definition-time validation, and the per-format mapped-field source.
      # Every serializer touchpoint is a thin identity check that delegates here.
      class Union < Value
        # Options that cannot be combined with a union member list.
        INCOMPATIBLE_OPTIONS = %i[polymorphic raw with child_mappings].freeze

        # Native Ruby class a parsed/plain-Ruby value already has when it
        # conforms to a scalar member without needing a lexical-space parse.
        NATIVE_CLASSES = {
          Lutaml::Model::Type::Integer => ::Integer,
          Lutaml::Model::Type::Float => ::Float,
          Lutaml::Model::Type::Boolean => [::TrueClass, ::FalseClass],
          Lutaml::Model::Type::String => ::String,
        }.freeze

        # Native classes for value types whose dependency loads lazily
        # (require "bigdecimal" / "date"). Looked up by constant name so the
        # union never force-loads an optional dependency; if such a value
        # exists at runtime, its constant is necessarily already defined.
        # Decimal's native class (BigDecimal) loads lazily (require
        # "bigdecimal"); looked up by constant name so the union never
        # force-loads it. (Decimal is the only supported value type with a
        # lazily-loaded native class.)
        LAZY_NATIVE_CLASS_NAMES = {
          Lutaml::Model::Type::Decimal => :BigDecimal,
        }.freeze

        INTEGER_LEXICAL = /\A\s*[+-]?\d+\s*\z/
        # Matches Type::Boolean.cast (XSD true/false/1/0 plus the library's
        # t/f/yes/no/y/n forms), so a union :boolean accepts the same inputs as
        # a plain :boolean attribute.
        BOOLEAN_LEXICAL = /\A(true|false|t|f|yes|no|y|n|1|0)\z/i

        FLOAT_LEXICAL = lambda do |string|
          Float(string).finite?
        rescue ArgumentError, TypeError
          false
        end

        # Whether a String input belongs to a scalar member's lexical space.
        # Keyed by member class (identity), parallel to NATIVE_CLASSES.
        LEXICAL_PREDICATES = {
          Lutaml::Model::Type::Integer => ->(s) { s.match?(INTEGER_LEXICAL) },
          Lutaml::Model::Type::Float => FLOAT_LEXICAL,
          Lutaml::Model::Type::Decimal => FLOAT_LEXICAL,
          Lutaml::Model::Type::Boolean => ->(s) { s.match?(BOOLEAN_LEXICAL) },
          Lutaml::Model::Type::String => ->(_s) { true },
        }.freeze

        # Sound scalar union members are exactly the value types with a lexical
        # predicate above: each maps to a distinct, stable Ruby runtime class
        # (Integer, Float, BigDecimal, TrueClass/FalseClass, String), so the
        # stateless value.class-driven serialization can always recover the
        # member. Other value types are excluded because they cannot round-trip
        # soundly in a union — e.g. Type::Date.cast can yield a DateTime, and
        # Time / TimeWithoutDate share a Ruby Time class. Models are always OK.
        SUPPORTED_VALUE_TYPES = LEXICAL_PREDICATES.keys.freeze

        class << self
          # Resolve the first member (in declared order) whose lexical/structural
          # space the value belongs to, and the value cast to that member.
          #
          # @param value [Object] raw value (scalar, Hash sub-tree, or XmlElement)
          # @param members [Array<Class>] resolved members, declared order
          # @param format [Symbol, nil] serialization format being deserialized
          # @param register [Symbol, nil] register for nested-model resolution
          # @return [Array(Class, Object), nil] [member, casted] or nil (no match)
          def conforming_member(value, members, format:, register:)
            return nil if value.nil? || Utils.uninitialized?(value)

            members.each do |member|
              casted = if model_member?(member)
                         conform_model(member, value, format, register)
                       else
                         conform_scalar(member, value)
                       end
              return [member, casted] unless casted == :no_match
            end
            nil
          end

          # Whether a compiled mapping rule's attribute is a union — the single
          # identity check every serializer touchpoint shares.
          def rule?(rule)
            rule.attribute_type == self
          end

          # Whether the value is already an instance of a model member. Used to
          # keep the plain-Ruby setter idempotent without re-running scalar
          # lexical resolution (which must still run for raw scalar inputs).
          def model_member_instance?(value, members)
            members.any? { |member| model_member?(member) && value.is_a?(member) }
          end

          # An XML child is routed to member resolution (vs the plain-text
          # scalar path) when it has child elements or attributes. Resolution
          # tries model members by key coverage, then falls back to the scalar
          # members on the element's text — so a text-only element with an
          # unrelated attribute (e.g. xml:lang) still resolves to a scalar.
          def xml_structured?(element)
            return false unless element.respond_to?(:children)

            element.children.any?(&:element?) || element.attributes.any?
          end

          # Whether a (possibly collection) value is already resolved to a model
          # member instance — used to keep XML normalize idempotent.
          def xml_resolved?(value, members)
            Array(value).any? { |element| model_member_instance?(element, members) }
          end

          # Serialize a scalar union value through the value type matching its
          # own class, so output is canonical/portable (a BigDecimal emits
          # "1.5", not a raw Ruby object). value.class drives the type —
          # stateless, identical to how a plain scalar attribute serializes.
          # Falls back to the value as-is when it maps to no known value type.
          def serialize_scalar(value, format)
            type = scalar_type_for(value)
            return value unless type

            type.new(value).public_send(:"to_#{format}")
          end

          def validate_members!(members)
            unless members.is_a?(::Array) && !members.empty?
              raise ArgumentError, "union type must be a non-empty array of types"
            end

            resolved = members.map { |member| resolve_member!(member) }
            validate_catch_all_position!(resolved)
            resolved
          end

          def validate_combo!(options)
            present = INCOMPATIBLE_OPTIONS.select { |key| options[key] }
            return if present.empty?

            raise ArgumentError,
                  "union type cannot be combined with: #{present.join(', ')}"
          end

          private

          def model_member?(member)
            member.is_a?(::Class) && member.include?(Serialize)
          end

          # Structural (key-coverage) selection: every input key maps to one of
          # the member's mapped fields, with no input key left unmapped. Once
          # selected, field values cast leniently via the member's normal path.
          def conform_model(member, value, format, register)
            keys = input_keys(value, format)
            return :no_match if keys.nil? || keys.empty?

            field_names = member_field_names(member, format, register)
            return :no_match unless keys.all? { |key| field_names.include?(key) }

            # Plain-Ruby assignment (format nil) builds straight from the
            # attribute hash, mirroring how non-union model attributes accept
            # `Model.new(child: { ... })`; a format builds via the mappings.
            return member.new(value) if format.nil?

            member.apply_mappings(value, format, register: register)
          end

          # A scalar conforms if the value already is the member's native Ruby
          # class (covers parsed and plain-Ruby values), or if a String input
          # belongs to the member's space. Lenient built-ins (Integer/Float/
          # Decimal/Boolean/String) are gated by an explicit lexical predicate
          # so their forgiving casts can't false-match; every other value type
          # owns its space via its own (strict) cast — nil/raise means no match.
          def conform_scalar(member, value)
            # Scalar payload: an XML element contributes its text (so a scalar
            # member matches when no model member covers it); Hash and primitive
            # inputs pass through unchanged.
            value = value.text if xml_element?(value)

            # Exact native class (instance_of?): the value is precisely the
            # member's native Ruby class (covers parsed and plain-Ruby values).
            native = Array(NATIVE_CLASSES[member] || lazy_native_class(member))
            return value if native.any? { |klass| value.instance_of?(klass) }

            predicate = LEXICAL_PREDICATES[member]
            return :no_match unless predicate

            # String input: accept only within the member's lexical space.
            if value.is_a?(::String)
              return predicate.call(value) ? member.cast(value) : :no_match
            end

            # Native non-string value (e.g. a parsed Integer for a :float
            # member): accept only if the member casts it losslessly, so a
            # lenient built-in can't silently distort it — :float accepts 42,
            # but :integer won't swallow 3.7.
            lossless_cast(member, value)
          end

          # A native non-string value conforms to a lenient built-in only if the
          # member's cast preserves it (value-equal round-trip), so cross-numeric
          # widening is accepted but narrowing/distortion is not.
          def lossless_cast(member, value)
            casted = member.cast(value)
            casted == value ? casted : :no_match
          rescue StandardError
            :no_match
          end

          def lazy_native_class(member)
            const_name = LAZY_NATIVE_CLASS_NAMES[member]
            return nil unless const_name && Object.const_defined?(const_name)

            Object.const_get(const_name)
          end

          # The value type whose native Ruby class the value is an instance of
          # (reverse of NATIVE_CLASSES plus the lazily-loaded native classes).
          def scalar_type_for(value)
            NATIVE_CLASSES.each do |type, klasses|
              return type if Array(klasses).any? { |k| value.instance_of?(k) }
            end
            LAZY_NATIVE_CLASS_NAMES.each_key do |type|
              klass = lazy_native_class(type)
              return type if klass && value.instance_of?(klass)
            end
            nil
          end

          # Input keys by format: Hash keys for key-value; child element local
          # names + attribute names for XML; nil otherwise.
          def input_keys(value, format)
            return value.keys.map(&:to_s) if value.is_a?(::Hash)

            if format == :xml && xml_element?(value)
              names = value.children.select(&:element?).map(&:unprefixed_name) +
                value.attributes.values.map(&:unprefixed_name)
              return names.map(&:to_s)
            end

            nil
          end

          def xml_element?(value)
            value.respond_to?(:children) && value.respond_to?(:attributes)
          end

          # The set of mapped field names for a member in the given format.
          # One source, parameterized by format. A nil format is plain-Ruby
          # assignment, which has no mapping context — match on attribute names.
          def member_field_names(member, format, register)
            return member.attributes.keys.map(&:to_s) if format.nil?

            mapping = member.mappings_for(format, register)
            rules = if format == :xml
                      mapping.elements(register) + mapping.attributes(register)
                    else
                      mapping.mappings(register)
                    end
            rules.map { |rule| rule.name.to_s }
          end

          def resolve_member!(member)
            if member.is_a?(::Hash)
              raise ArgumentError,
                    "union members must be types or symbols; option hashes " \
                    "(e.g. { ref: ... }) are not supported as union members"
            end

            klass =
              begin
                Lutaml::Model::Attribute.cast_type!(member)
              rescue ArgumentError
                nil
              end
            unless klass
              raise ArgumentError, "invalid union member: #{member.inspect}"
            end
            return klass if klass.is_a?(::Class) && klass.include?(Serialize)
            return klass if SUPPORTED_VALUE_TYPES.include?(klass)

            raise ArgumentError,
                  "unsupported union member type: #{member.inspect}. Supported " \
                  "scalar members are :string, :integer, :float, :decimal, " \
                  ":boolean, or a Serializable model"
          end

          def validate_catch_all_position!(resolved)
            catch_all_index = resolved.index(Lutaml::Model::Type::String)
            return if catch_all_index.nil?

            last_value_index = resolved.rindex { |member| member <= Value }
            return if catch_all_index == last_value_index

            raise ArgumentError,
                  "a universal catch-all type must be the last union member"
          end
        end
      end
    end
  end
end
