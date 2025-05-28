# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class Restriction
          attr_accessor :min_inclusive,
                        :max_inclusive,
                        :min_exclusive,
                        :max_exclusive,
                        :enumerations,
                        :max_length,
                        :min_length,
                        :base_class,
                        :pattern,
                        :length

            MAX_BOUND = ERB.new(<<~TEMPLATE, trim_mode: "-")
              <%= "\#{indent}max_bound = \#{max_inclusive || max_exclusive}" %>
              <%= "\#{indent}raise_max_bound_error(value, max_bound) unless value < \#{'=' if max_inclusive} max_bound" %>
            TEMPLATE

            MIN_BOUND = ERB.new(<<~TEMPLATE, trim_mode: "-")
              <%= "\#{indent}min_bound = \#{min_inclusive || min_exclusive}" %>
              <%= "\#{indent}raise_min_bound_error(value, min_bound) unless value >\#{'=' if min_inclusive} min_bound" %>
            TEMPLATE

            PATTERN = ERB.new(<<~TEMPLATE, trim_mode: "-")
              <%= "\#{indent}pattern = %r{\#{pattern}}" %>
              <%= "\#{indent}raise_pattern_error(value, pattern) unless value.match?(pattern)" %>
            TEMPLATE

            MAX_BOUND_ERROR_METHOD = ERB.new(<<~TEMPLATE, trim_mode: "-")
              <%= indent %>def self.raise_max_bound_error(input_value, max_bound)
              <%= indent %>  raise Lutaml::Model::Type::InvalidValueError, "The provided value \#{input_value} exceeds the maximum allowed value of \#{max_bound}"
              <%= indent %>end
            TEMPLATE

            MIN_BOUND_ERROR_METHOD = ERB.new(<<~TEMPLATE, trim_mode: "-")
              <%= indent %>def self.raise_min_bound_error(input_value, min_bound)
              <%= indent %>  raise Lutaml::Model::Type::InvalidValueError, "The provided value \#{input_value} is less than the minimum allowed value of \#{min_bound}"
              <%= indent %>end
            TEMPLATE

            PATTERN_ERROR_METHOD = ERB.new(<<~TEMPLATE, trim_mode: "-")
              <%= indent %>def self.raise_pattern_error(input_value, pattern)
              <%= indent %>  raise Lutaml::Model::Type::InvalidValueError, "The provided value \#{input_value} does not match the pattern \#{pattern}"
              <%= indent %>end
            TEMPLATE

          def to_method_body(indent = nil)
            [
              value_for(MAX_BOUND, type: :max_bound, indent: indent),
              value_for(MIN_BOUND, type: :min_bound, indent: indent),
              value_for(PATTERN, type: :pattern, indent: indent),
            ].compact.join("\n")
          end

          def to_error_methods(indent = nil)
            [
              value_for(MAX_BOUND_ERROR_METHOD, type: :max_bound, indent: indent),
              value_for(MIN_BOUND_ERROR_METHOD, type: :min_bound, indent: indent),
              value_for(PATTERN_ERROR_METHOD, type: :pattern, indent: indent),
            ].compact.join("\n")
          end

          def error_methods?
            min_bound_exist? || max_bound_exist? || pattern_exist?
          end

          private

          def value_for(constant, type:, indent:)
            return unless send("#{type}_exist?")

            indent ||= "  "
            constant.result(binding)
          end

          def min_bound_exist?
            min_inclusive || min_exclusive
          end

          def max_bound_exist?
            max_inclusive || max_exclusive
          end

          def pattern_exist?
            Utils.present?(pattern)
          end
        end
      end
    end
  end
end
