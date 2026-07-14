# frozen_string_literal: true

module Lutaml
  module Model
    # Module for enforcing value restrictions on attributes.
    #
    # Provides the lazy validation seam used by `Attribute#validate_value!`:
    # a configuration check (applicability of the effective facets to the
    # resolved type) and a value check (ordered bounds / string length) that
    # reuses the shared Type validators and translates their errors into
    # model-level errors carrying the attribute name.
    #
    # The effective facet set is the conjunctive merge of Layer-1 attribute
    # options (lowered to canonical keys) and the Layer-2 facets declared on a
    # `Type::Value` subclass; the tightest constraint per key wins.
    module RestrictionValidation
      # Verify the effective facets are applicable to the resolved type. The
      # type is only known after register resolution, so this runs at
      # validation time and raises ahead of the value checks.
      def validate_restriction_configuration!(resolved_type)
        facets = effective_facets(resolved_type)

        if @options.key?(:signed) && !numeric_type?(resolved_type)
          raise ArgumentError,
                "Invalid options for `#{name}`: " \
                "`signed` is only allowed for numeric types"
        end

        if ordered_facets?(facets) && !ordered_type?(resolved_type)
          raise ArgumentError,
                "Invalid options for `#{name}`: " \
                "`min`, `max`, `inclusive` and `exclusive` are only allowed " \
                "for numeric types or temporal (date/time) types"
        end

        if length_facets?(facets) && !string_type?(resolved_type)
          raise ArgumentError,
                "Invalid options for `#{name}`: " \
                "`min_length` and `max_length` are only allowed for :string type"
        end

        if facets.key?(:pattern) && !string_type?(resolved_type)
          raise ArgumentError,
                "Invalid options for `#{name}`: " \
                "`pattern` is only allowed for string-derived types"
        end

        if digit_facets?(facets) && !digit_type?(resolved_type)
          raise ArgumentError,
                "Invalid options for `#{name}`: " \
                "`total_digits` and `fraction_digits` are only allowed " \
                "for :integer and :decimal types"
        end
      end

      # Enforce the effective facets against the value, translating the reused
      # validator's Type::* errors into model-level errors that carry the
      # attribute name so `validate` can collect them.
      def validate_restriction_values!(value, resolved_type)
        facets = effective_facets(resolved_type)
        return if facets.empty?
        return if value.nil? || Utils.uninitialized?(value)

        unless collection? && collection_instance?(value)
          return validate_element_facets!(value, resolved_type, facets)
        end

        value.each do |element|
          next if element.nil? || Utils.uninitialized?(element)

          validate_element_facets!(element, resolved_type, facets)
        end
      end

      # Effective facet set for schema emission: the validator's merge plus the
      # pre-#191 `values:`/`pattern:` options. Those are enforced at runtime by
      # a separate path (so they are absent from the validation facet set); fold
      # them in here so the exported XSD is not weaker than what is enforced.
      def effective_restriction_facets(resolved_type)
        facets = effective_facets(resolved_type)
        facets = merge_values_option(facets, resolved_type) if @options.key?(:values)
        facets = merge_pattern_option(facets) if @options.key?(:pattern)
        # Folding in the values: option can empty an enumeration (a disjoint
        # set enforced by both layers); that is an unsatisfiable restriction,
        # not an unrestricted one, so reject it as the merged interval does.
        reject_empty_enumeration!(facets)
        facets
      end

      private

      # Value facets apply to a single value: the whole value for a singular
      # attribute, or each present element for a collection. Cardinality (item
      # count) is governed separately by `collection:` in the `&&`-chain.
      def validate_element_facets!(value, resolved_type, facets)
        if ordered_type?(resolved_type)
          validate_inclusive_bounds!(value, facets)
          validate_exclusive_bounds!(value, facets)
        end
        if string_type?(resolved_type)
          # Length and pattern facets operate on the lexical (serialized) form:
          # a string-derived type whose cast value is not a ::String (e.g.
          # Type::Uri holding a ::URI) has no #length/#match?, so measuring or
          # matching the raw cast object would raise. Serialize once, share it.
          lexical = resolved_type.serialize(value)
          validate_length_bounds!(value, lexical, facets)
          validate_patterns!(value, lexical, facets)
        end
        validate_digit_bounds!(value, facets) if digit_type?(resolved_type)
        validate_enumeration!(value, facets)
      end

      # Conjunctive merge of Layer-1 options and Layer-2 type facets, both in
      # canonical-key form. Ordered bounds and enumeration members are cast to
      # the resolved type per layer (before the merge, so `tighter_facet`/`&`
      # compare homogeneous values). An empty resulting interval is a config
      # error.
      def effective_facets(resolved_type)
        facets = option_facets(resolved_type)
          .merge(type_facets(resolved_type)) do |key, a, b|
            Type::Value.tighter_facet(key, a, b)
          end
        ensure_consistent_interval!(facets)
        facets
      end

      def option_facets(resolved_type)
        facets = {}
        facets[:min_inclusive] = cast_bound(@options[:min], resolved_type) if @options.key?(:min)
        facets[:max_inclusive] = cast_bound(@options[:max], resolved_type) if @options.key?(:max)
        if @options[:signed] == false
          zero = cast_bound(0, resolved_type)
          facets[:min_inclusive] = [facets[:min_inclusive], zero].compact.max
        end
        facets[:min_length] = @options[:min_length] if @options.key?(:min_length)
        facets[:max_length] = @options[:max_length] if @options.key?(:max_length)
        # An explicit `min: nil` / `max: nil` means "no bound": drop the nil
        # key so it neither emits an empty <xs:restriction> nor masks a genuinely
        # empty interval during consolidation.
        facets.compact
      end

      # Layer-2 facets are already cast to the type at declaration; only the
      # Layer-1 option bounds (below) still need casting.
      def type_facets(resolved_type)
        return {} unless castable_type?(resolved_type)

        resolved_type.facets
      end

      # Fold the Layer-1 `values:` option into the schema enumeration. Runtime
      # enforces both sets conjunctively, so a Layer-2 enumeration is
      # intersected with the values option (both cast to the type so the
      # intersection compares like values).
      def merge_values_option(facets, resolved_type)
        members = Array(@options[:values]).map { |v| cast_bound(v, resolved_type) }
        existing = facets[:enumeration]
        facets.merge(enumeration: existing ? existing & members : members)
      end

      # Fold the Layer-1 `pattern:` option into the schema pattern list (the
      # emitter fails fast if that yields conjunctive patterns XSD cannot OR).
      def merge_pattern_option(facets)
        option = @options[:pattern]
        regexp = option.is_a?(Regexp) ? option : Regexp.new(option)
        facets.merge(pattern: Array(facets[:pattern]) + [regexp])
      end

      def cast_bound(value, resolved_type)
        return value unless castable_type?(resolved_type)

        cast_facet_value(value, resolved_type)
      end

      # Cast a bound/enumeration literal to the resolved type. A non-nil literal
      # that casts to nil is an unparseable restriction (e.g. `min: "abc"` on an
      # integer); raise rather than silently drop the constraint.
      def cast_facet_value(value, resolved_type)
        cast = resolved_type.cast(value)
        return cast if !cast.nil? || value.nil?

        raise ArgumentError,
              "Invalid restrictions for `#{name}`: " \
              "#{value.inspect} is not a valid #{resolved_type} value"
      end

      def castable_type?(resolved_type)
        resolved_type.is_a?(Class) && resolved_type <= Type::Value
      end

      def ensure_consistent_interval!(facets)
        consolidate_min_bounds!(facets)
        consolidate_max_bounds!(facets)
        reject_empty_ordered_interval!(facets)
        reject_empty_interval!(facets, :min_length, :max_length)
        reject_exact_length_conflict!(facets)
        reject_empty_enumeration!(facets)
        reject_fraction_exceeding_total!(facets)
      end

      # A same-side inclusive+exclusive pair is a conjunction (both must hold),
      # so the tighter bound binds and the looser one is dropped. Lower side:
      # `>= inc AND > exc`; inclusive binds only when it excludes strictly more
      # (`inc > exc`), otherwise the exclusive bound wins (tie included, since
      # `> n` is tighter than `>= n`).
      def consolidate_min_bounds!(facets)
        inc = facets[:min_inclusive]
        exc = facets[:min_exclusive]
        return if inc.nil? || exc.nil?

        facets.delete(inc > exc ? :min_exclusive : :min_inclusive)
      end

      # Upper side: `<= inc AND < exc`; inclusive binds only when it excludes
      # strictly more (`inc < exc`), otherwise the exclusive bound wins (tie
      # included, since `< n` is tighter than `<= n`).
      def consolidate_max_bounds!(facets)
        inc = facets[:max_inclusive]
        exc = facets[:max_exclusive]
        return if inc.nil? || exc.nil?

        facets.delete(inc < exc ? :max_exclusive : :max_inclusive)
      end

      def reject_fraction_exceeding_total!(facets)
        total = facets[:total_digits]
        fraction = facets[:fraction_digits]
        return if total.nil? || fraction.nil? || fraction <= total

        raise ArgumentError,
              "Invalid restrictions for `#{name}`: " \
              "fraction_digits (#{fraction}) exceeds total_digits (#{total})"
      end

      def reject_empty_enumeration!(facets)
        enumeration = facets[:enumeration]
        return if enumeration.nil? || !enumeration.empty?

        raise ArgumentError,
              "Invalid restrictions for `#{name}`: " \
              "enumeration allows no values"
      end

      # Reject an empty interval formed by the merged ordered bounds. After
      # consolidation at most one lower and one upper bound remain; a shared
      # endpoint is valid only when both bounds are inclusive (single point).
      def reject_empty_ordered_interval!(facets)
        lo_key = facets.key?(:min_inclusive) ? :min_inclusive : :min_exclusive
        hi_key = facets.key?(:max_inclusive) ? :max_inclusive : :max_exclusive
        lo = facets[lo_key]
        hi = facets[hi_key]
        return if lo.nil? || hi.nil?

        if lo > hi
          raise ArgumentError,
                "Invalid restrictions for `#{name}`: " \
                "#{lo_key} (#{lo}) exceeds #{hi_key} (#{hi})"
        end

        return unless lo == hi
        return if lo_key == :min_inclusive && hi_key == :max_inclusive

        raise ArgumentError,
              "Invalid restrictions for `#{name}`: " \
              "#{lo_key} (#{lo}) and #{hi_key} (#{hi}) define an empty interval"
      end

      def reject_empty_interval!(facets, min_key, max_key)
        min = facets[min_key]
        max = facets[max_key]
        return if min.nil? || max.nil? || min <= max

        raise ArgumentError,
              "Invalid restrictions for `#{name}`: " \
              "#{min_key} (#{min}) exceeds #{max_key} (#{max})"
      end

      def reject_exact_length_conflict!(facets)
        length = facets[:length]
        min = facets[:min_length]
        max = facets[:max_length]
        return if length.nil?
        return if (min.nil? || length >= min) && (max.nil? || length <= max)

        raise ArgumentError,
              "Invalid restrictions for `#{name}`: " \
              "length (#{length}) is outside [#{min}, #{max}]"
      end

      def ordered_facets?(facets)
        facets.key?(:min_inclusive) || facets.key?(:max_inclusive) ||
          facets.key?(:min_exclusive) || facets.key?(:max_exclusive)
      end

      def length_facets?(facets)
        facets.key?(:min_length) || facets.key?(:max_length) ||
          facets.key?(:length)
      end

      def digit_facets?(facets)
        facets.key?(:total_digits) || facets.key?(:fraction_digits)
      end

      # Digit facets are countable only on integer- and decimal-derived types.
      # Float is intentionally excluded: its binary representation makes the
      # significant-digit count unreliable.
      def digit_type?(resolved_type)
        resolved_type <= Type::Integer || resolved_type <= Type::Decimal
      end

      def ordered_type?(resolved_type)
        numeric_type?(resolved_type) || temporal_type?(resolved_type)
      end

      def numeric_type?(resolved_type)
        resolved_type <= Type::Integer ||
          resolved_type <= Type::Decimal ||
          resolved_type <= Type::Float
      end

      # Ordered facets apply to temporal types whose cast value has a reliable
      # total order (Date/Time/DateTime respond to <=>). Duration and
      # TimeWithoutDate are intentionally excluded: their cast value is a
      # lexical String, so comparing them as ordered bounds would be incorrect.
      def temporal_type?(resolved_type)
        resolved_type <= Type::Date ||
          resolved_type <= Type::Time ||
          resolved_type <= Type::DateTime
      end

      def string_type?(resolved_type)
        resolved_type <= Type::String
      end

      def validate_inclusive_bounds!(value, facets)
        bounds = { min: facets[:min_inclusive],
                   max: facets[:max_inclusive] }.compact
        return if bounds.empty?

        Services::Type::Validator.validate_min_max_bounds!(value, bounds)
      rescue Lutaml::Model::Type::MinBoundError
        raise Lutaml::Model::MinInclusiveError.new(name, value, bounds[:min])
      rescue Lutaml::Model::Type::MaxBoundError
        raise Lutaml::Model::MaxInclusiveError.new(name, value, bounds[:max])
      end

      def validate_exclusive_bounds!(value, facets)
        min = facets[:min_exclusive]
        max = facets[:max_exclusive]
        return if min.nil? && max.nil?

        Services::Type::Validator.validate_exclusive_bounds!(value, facets)
      rescue Lutaml::Model::Type::MinExclusiveError
        raise Lutaml::Model::MinExclusiveError.new(name, value, min)
      rescue Lutaml::Model::Type::MaxExclusiveError
        raise Lutaml::Model::MaxExclusiveError.new(name, value, max)
      end

      # `lexical` is the serialized form measured for length; `value` is the
      # original cast value carried in the model error (as the pattern path does).
      def validate_length_bounds!(value, lexical, facets)
        validate_exact_length!(value, lexical, facets[:length])
        min = facets[:min_length]
        max = facets[:max_length]
        Services::Type::Validator::String.validate_min_length!(lexical, min) if min
        Services::Type::Validator::String.validate_max_length!(lexical, max) if max
      rescue Lutaml::Model::Type::MinLengthError
        raise Lutaml::Model::MinLengthError.new(name, value, min)
      rescue Lutaml::Model::Type::MaxLengthError
        raise Lutaml::Model::MaxLengthError.new(name, value, max)
      end

      def validate_exact_length!(value, lexical, length)
        return if length.nil? || lexical.length == length

        raise Lutaml::Model::LengthError.new(name, value, length)
      end

      def validate_digit_bounds!(value, facets)
        total_limit = facets[:total_digits]
        fraction_limit = facets[:fraction_digits]
        return if total_limit.nil? && fraction_limit.nil?

        total, fraction = digit_counts(value)
        if total_limit && total > total_limit
          raise Lutaml::Model::TotalDigitsError.new(name, value, total_limit)
        end
        return unless fraction_limit && fraction > fraction_limit

        raise Lutaml::Model::FractionDigitsError.new(name, value, fraction_limit)
      end

      # Count digits of an already-cast numeric value using XSD semantics
      # (xs:totalDigits / xs:fractionDigits). From the fixed-notation string
      # drop the sign and strip trailing zeros from the fraction part; the
      # significand is the integer part concatenated with that fraction, with
      # leading zeros removed. total = significant digits in the significand;
      # fraction = remaining fraction digits. A leading zero before the point
      # (values < 1) is insignificant, so `0.05` is [1, 2]; zero is [0, 0].
      #
      # @return [Array(Integer, Integer)] [total_digits, fraction_digits]
      def digit_counts(value)
        fixed = value.is_a?(::Integer) ? value.to_s : value.to_s("F")
        int_part, frac_part = fixed.delete("-").split(".")
        significant_frac = frac_part.to_s.sub(/0+\z/, "")
        significand = (int_part + significant_frac).sub(/\A0+/, "")
        [significand.length, significant_frac.length]
      end

      def validate_enumeration!(value, facets)
        allowed = facets[:enumeration]
        return if allowed.nil?

        Services::Type::Validator.validate_values!(value, allowed)
      rescue Lutaml::Model::Type::InvalidValueError
        raise Lutaml::Model::InvalidValueError.new(name, value, allowed)
      end

      # Each accumulated pattern must match against the lexical form (already
      # serialized by the caller) so non-::String string-derived types are
      # matched on their serialized text rather than their cast object; the
      # model error still carries the original `value`.
      def validate_patterns!(value, lexical, facets)
        patterns = facets[:pattern]
        return if patterns.nil?

        patterns.each do |pattern|
          Services::Type::Validator::String.validate_pattern!(
            lexical, pattern: pattern
          )
        rescue Lutaml::Model::Type::PatternNotMatchedError
          raise Lutaml::Model::PatternNotMatchedError.new(name, pattern, value)
        end
      end
    end
  end
end
