# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      # Base class for all value types
      class Value
        prepend UninitializedClassGuard

        # Performance optimization: reusable empty options hash
        # Use options.equal?(EMPTY_OPTIONS) for fast-path checks
        EMPTY_OPTIONS = {}.freeze

        # Canonical facet keys grouped by how a tighter constraint compares: a
        # min-like facet tightens upward (greater wins), a max-like facet
        # tightens downward (lesser wins). `:length` (exact) only matches equal.
        MIN_FACETS = %i[min_inclusive min_exclusive min_length].freeze
        MAX_FACETS = %i[
          max_inclusive
          max_exclusive
          max_length
          total_digits
          fraction_digits
        ].freeze

        # Facets whose combined value is the concatenation of every declaration
        # in the chain: accumulating them is always a tightening (all patterns
        # must match), so they bypass the widen check on inheritance.
        LIST_FACETS = %i[pattern].freeze

        # xs:whiteSpace normalization modes in ascending strictness: a stricter
        # mode transforms at least as much as a looser one, so `tighter_facet`
        # picks the stricter and a subclass may tighten but not loosen it.
        WHITE_SPACE_MODES = %i[preserve replace collapse].freeze

        # Format type serializer registry
        # Keys: [format, TypeClass] => { to: Proc, from: Proc }
        @format_type_serializers = {}

        class << self
          # Register a custom type serializer for a specific format and type class.
          # Format plugins call this at load time to register their custom serialization logic.
          #
          # @param format [Symbol] the format (e.g., :xml, :json)
          # @param type_class [Class] the type class (must be <= Value)
          # @param to [Proc, nil] custom instance serialization proc (receives the type instance)
          # @param from [Proc, nil] custom class deserialization proc (receives the raw value)
          def register_format_type_serializer(format, type_class, to: nil,
from: nil)
            @format_type_serializers[[format, type_class]] =
              { to: to, from: from }.compact
          end

          # Look up a format type serializer, walking the class hierarchy.
          #
          # @param format [Symbol] the format
          # @param type_class [Class] the type class to look up
          # @return [Hash, nil] { to: Proc, from: Proc } or nil
          def format_type_serializer_for(format, type_class)
            klass = type_class
            while klass && klass <= Value
              s = @format_type_serializers[[format, klass]]
              return s if s

              klass = klass.superclass
            end
            nil
          end

          # Freeze a type's facets to further declarations once it is
          # subclassed, so a parent cannot widen facets after children exist.
          def inherited(subclass)
            super
            @facets_closed = true
          end

          # Effective canonical facets for this type, merged parent-first. A
          # subclass may only tighten an inherited facet; widening raises.
          def facets
            facet_layers.each_with_object({}) do |layer, merged|
              layer.each do |key, value|
                merged[key] = inherit_facet(key, merged[key], value)
              end
            end
          end

          # Conjunctive-merge primitive for two facet values of the same key:
          # the tighter one wins (greater for min-like, lesser for max-like),
          # an exact `:length` must agree. The canonical home for facet
          # combination, reused by the Layer-1/Layer-2 merge.
          def tighter_facet(key, existing, incoming)
            return incoming if existing.nil?
            return existing if incoming.nil?
            return incoming & existing if key == :enumeration
            return existing + incoming if LIST_FACETS.include?(key)
            return [existing, incoming].max if MIN_FACETS.include?(key)
            return [existing, incoming].min if MAX_FACETS.include?(key)
            return stricter_white_space(existing, incoming) if key == :white_space
            return existing if existing == incoming

            raise ArgumentError,
                  "conflicting `#{key}` facets: #{existing} and #{incoming}"
          end

          # Constrain ordered values via min/maxInclusive.
          def inclusive(min: nil, max: nil)
            raise_unordered!("inclusive", min, max)
            declare_facets(min_inclusive: min, max_inclusive: max)
          end

          # Constrain ordered values via min/maxExclusive.
          def exclusive(min: nil, max: nil)
            raise_unordered!("exclusive", min, max)
            declare_facets(min_exclusive: min, max_exclusive: max)
          end

          # Constrain length: exact `length N`, or `length min:, max:`.
          def length(exact = nil, min: nil, max: nil)
            return declare_exact_length(exact, min, max) unless exact.nil?

            raise_unordered!("length", min, max)
            raise_negative_length!(min)
            raise_negative_length!(max)
            declare_facets(min_length: min, max_length: max)
          end

          # Restrict to an enumerated set of allowed values (any type). A
          # subclass narrows the parent's set; the effective set is the
          # intersection across the chain (see `tighter_facet`).
          def enumeration(*values)
            declare_facets(enumeration: values)
          end

          # Restrict a string-derived value to match a regular expression. A
          # String argument is compiled to a Regexp. Patterns accumulate across
          # the chain; a value must match all of them.
          def pattern(regex_or_string)
            regexp = regex_or_string.is_a?(Regexp) ? regex_or_string : Regexp.new(regex_or_string)
            declare_facets(pattern: [regexp])
          end

          # Normalize a string-derived value's whitespace at cast time
          # (xs:whiteSpace). Unlike every other facet this transforms the
          # stored value rather than validating it, so it is applied in
          # `String.cast`, not the lazy validator. Only string-derived types
          # carry lexical text, so declaring it elsewhere fails fast.
          def white_space(mode)
            unless self <= Type::String
              raise ArgumentError,
                    "`white_space` is only allowed for string-derived types"
            end
            unless WHITE_SPACE_MODES.include?(mode)
              raise ArgumentError,
                    "`white_space` must be one of " \
                    "#{WHITE_SPACE_MODES.map(&:inspect).join(', ')}"
            end

            declare_facets(white_space: mode)
          end

          # Cap the total number of significant digits (xs:totalDigits) an
          # integer- or decimal-derived value may carry. A maximum; the value
          # must have at most `count` significant digits. Applicability to the
          # resolved type is enforced lazily at validation time.
          def total_digits(count)
            declare_digit_facet(:total_digits, count, minimum: 1)
          end

          # Cap the number of significant fraction digits (xs:fractionDigits) an
          # integer- or decimal-derived value may carry (a maximum).
          def fraction_digits(count)
            declare_digit_facet(:fraction_digits, count, minimum: 0)
          end

          private

          def declare_digit_facet(key, count, minimum:)
            unless count.is_a?(::Integer) && count >= minimum
              raise ArgumentError,
                    "`#{key}` must be an Integer >= #{minimum}, " \
                    "got #{count.inspect}"
            end

            declare_facets(key => count)
          end

          def stricter_white_space(existing, incoming)
            [existing, incoming].max_by { |mode| WHITE_SPACE_MODES.index(mode) }
          end

          def facet_layers
            layers = []
            klass = self
            while klass && klass <= Value
              own = klass.instance_variable_get(:@facets)
              layers.unshift(own) if own
              klass = klass.superclass
            end
            layers
          end

          def inherit_facet(key, inherited, declared)
            return declared if inherited.nil?
            if LIST_FACETS.include?(key)
              return tighter_facet(key, inherited, declared)
            end
            return declared if tighter_facet(key, inherited, declared) == declared

            raise ArgumentError,
                  "#{self} cannot widen inherited facet `#{key}` " \
                  "from #{inherited} to #{declared}"
          end

          def declare_exact_length(exact, min, max)
            unless min.nil? && max.nil?
              raise ArgumentError,
                    "`length #{exact}` cannot be combined with min:/max:"
            end

            raise_negative_length!(exact)
            declare_facets(length: exact)
          end

          def declare_facets(values)
            ensure_facets_open!
            facets = values.compact
            raise ArgumentError, "at least one facet value is required" if facets.empty?

            store = (@facets ||= {})
            facets.each do |key, value|
              store[key] = tighter_facet(key, store[key], value)
            end
            reset_facet_cache
          end

          # Hook: drop any per-class value derived from the facet set when a
          # facet is (re)declared, so a stale memo cannot outlive the facets it
          # was computed from. A no-op here; subclasses that memoize override it.
          def reset_facet_cache; end

          def ensure_facets_open!
            return unless @facets_closed

            raise ArgumentError,
                  "Cannot declare facets on #{self}: it already has subclasses"
          end

          def raise_unordered!(macro, min, max)
            return if min.nil? || max.nil? || min <= max

            raise ArgumentError,
                  "`#{macro}` min (#{min}) must not exceed max (#{max})"
          end

          def raise_negative_length!(value)
            return if value.nil? || value >= 0

            raise ArgumentError, "length facet must not be negative: #{value}"
          end
        end

        attr_reader :value

        def initialize(value)
          @value = self.class.cast(value)
        end

        def initialized?
          true
        end

        def self.cast(value, _options = {})
          return nil if value.nil?
          return value if Utils.uninitialized?(value)

          value
        end

        def self.serialize(value)
          return nil if value.nil?
          return value if Utils.uninitialized?(value)

          new(value).to_s
        end

        # Instance methods for serialization
        def to_s
          value.to_s
        end

        # Class-level format conversion
        def self.from_format(value, format)
          new(send(:"from_#{format}", value))
        end

        # Called from FormatRegistry when a new format is registered.
        # Defines to_{format} and from_{format} methods that check the
        # serializer registry first, falling back to default behavior.
        def self.register_format_to_from_methods(format)
          define_method(:"to_#{format}") do
            s = Value.format_type_serializer_for(format, self.class)
            s&.dig(:to) ? s[:to].call(self) : value
          end

          define_singleton_method(:"from_#{format}") do |v|
            s = Value.format_type_serializer_for(format, self)
            s&.dig(:from) ? s[:from].call(v) : cast(v)
          end
        end
      end
    end
  end
end
