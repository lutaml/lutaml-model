# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class Restriction
          # transform is not a 'xsd' type, but it is used for internal purposes.
          attr_accessor :min_inclusive,
                        :max_inclusive,
                        :min_exclusive,
                        :max_exclusive,
                        :enumerations,
                        :max_length,
                        :min_length,
                        :base_class,
                        :pattern,
                        :length,
                        :transform

          MIN_MAX_BOUNDS = ERB.new(<<~TEMPLATE, trim_mode: "-")
            <%= "\#{indent}options[:max] = \#{max_inclusive || max_exclusive}" if max_bound_exist? %>
            <%= "\#{indent}options[:min] = \#{min_inclusive || min_exclusive}" if min_bound_exist? %>
          TEMPLATE

          PATTERN = ERB.new(<<~TEMPLATE, trim_mode: "-")
            <%= "\#{indent}options[:pattern] = %r{\#{pattern}}" %>
          TEMPLATE

          ENUMERATIONS = ERB.new(<<~TEMPLATE, trim_mode: "-")
            <%= "\#{indent}options[:values] = [\#{casted_enumerations}]" %>
          TEMPLATE

          TRANSFORM = ERB.new(<<~TEMPLATE, trim_mode: "-")
            <%= "\#{indent}value = \#{transform}" %>
          TEMPLATE

          def to_method_body(indent = nil)
            [
              value_for(ENUMERATIONS, type: :enumerations, indent: indent),
              value_for(MIN_MAX_BOUNDS, type: :min_max_bounds, indent: indent),
              value_for(PATTERN, type: :pattern, indent: indent),
              value_for(TRANSFORM, type: :transform, indent: indent),
            ].compact.join
          end

          def required_files
            if base_class_name == :decimal
              "require \"bigdecimal\""
            elsif !SimpleType::SUPPORTED_DATA_TYPES.dig(base_class_name, :skippable)
              "require_relative \"#{Utils.snake_case(base_class_name)}\""
            end
          end

          private

          def value_for(constant, type:, indent:)
            return unless send("#{type}_exist?")

            indent ||= "  "
            constant.result(binding)
          end

          def min_max_bounds_exist?
            min_bound_exist? || max_bound_exist?
          end

          def min_bound_exist?
            Utils.present?(min_inclusive) || Utils.present?(min_exclusive)
          end

          def max_bound_exist?
            Utils.present?(max_inclusive) || Utils.present?(max_exclusive)
          end

          def pattern_exist?
            Utils.present?(pattern)
          end

          def enumerations_exist?
            Utils.present?(enumerations)
          end

          def transform_exist?
            Utils.present?(transform)
          end

          def base_class_name
            return if Utils.blank?(base_class)

            base_class.split(":").last.to_sym
          end

          def casted_enumerations
            enumerations.map { |enumeration| "super(#{enumeration.inspect})" }.join(", ")
          end
        end
      end
    end
  end
end
