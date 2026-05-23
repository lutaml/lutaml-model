# frozen_string_literal: true

require "erb"

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # Collects restriction facets parsed from RNG <data> <param> children
        # and/or <choice> <value> enumerations. Mirrors XmlCompiler::Restriction.
        # Renders the body of a `def self.cast(value, options = {})` method
        # used by SimpleType.
        class Restriction
          attr_accessor :min_inclusive, :max_inclusive,
                        :min_exclusive, :max_exclusive,
                        :min_length, :max_length, :length,
                        :pattern, :enumerations, :base_type

          MIN_MAX_BOUNDS = ERB.new(<<~TMPL, trim_mode: "-")
            <%= "\#{indent}options[:max] = \#{max_inclusive || max_exclusive}" if max_bound? %>
            <%= "\#{indent}options[:min] = \#{min_inclusive || min_exclusive}" if min_bound? %>
          TMPL

          PATTERN_TMPL = ERB.new(<<~TMPL, trim_mode: "-")
            <%= "\#{indent}options[:pattern] = %r{\#{pattern}}" if pattern_present? %>
          TMPL

          ENUMERATIONS_TMPL = ERB.new(<<~TMPL, trim_mode: "-")
            <%= "\#{indent}options[:values] = [\#{casted_enumerations}]" if enumerations_present? %>
          TMPL

          def initialize
            @enumerations = []
          end

          # Returns true when at least one facet has been collected.
          def any?
            min_bound? || max_bound? || pattern_present? ||
              enumerations_present? || min_length || max_length || length
          end

          def to_method_body(indent = "    ")
            [
              ENUMERATIONS_TMPL.result(binding),
              MIN_MAX_BOUNDS.result(binding),
              PATTERN_TMPL.result(binding),
            ].compact.reject(&:empty?).join
          end

          def add_param(name, value)
            case name
            when "minInclusive" then @min_inclusive = numeric_or_string(value)
            when "maxInclusive" then @max_inclusive = numeric_or_string(value)
            when "minExclusive" then @min_exclusive = numeric_or_string(value)
            when "maxExclusive" then @max_exclusive = numeric_or_string(value)
            when "minLength"    then @min_length = value.to_i
            when "maxLength"    then @max_length = value.to_i
            when "length"       then @length = value.to_i
            when "pattern"      then @pattern = value
            end
          end

          def add_enumeration(value)
            @enumerations << value
          end

          def min_bound?
            !@min_inclusive.nil? || !@min_exclusive.nil?
          end

          def max_bound?
            !@max_inclusive.nil? || !@max_exclusive.nil?
          end

          def pattern_present?
            !@pattern.nil? && !@pattern.empty?
          end

          def enumerations_present?
            !@enumerations.empty?
          end

          private

          def casted_enumerations
            @enumerations.map { |e| "super(#{e.inspect})" }.join(", ")
          end

          def numeric_or_string(value)
            return value.to_i if value =~ /\A-?\d+\z/
            return value.to_f if value =~ /\A-?\d+\.\d+\z/

            value
          end
        end
      end
    end
  end
end
