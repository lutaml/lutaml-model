# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module XmlCompiler
        class Restriction < Lutaml::Xsd::RestrictionSimpleType
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
              max_bound = <%= max_inclusive || max_exclusive %>
              raise_max_bound_error(value, max_bound) unless value <<%= '=' if max_inclusive %> max_bound
            TEMPLATE

            MIN_BOUND = ERB.new(<<~TEMPLATE, trim_mode: "-")
              min_bound = <%= min_inclusive || min_exclusive %>
              raise_min_bound_error(value, min_bound) unless value ><%= '=' if min_inclusive %> min_bound
            TEMPLATE

            MAX_BOUND_ERROR_METHOD = ERB.new(<<~TEMPLATE, trim_mode: "-")
              def self.raise_max_bound_error(input_value, max_bound)
                raise Lutaml::Model::Type::InvalidValueError, "The provided value \#{input_value} exceeds the maximum allowed value of \#{max_bound}"
              end
            TEMPLATE

            MIN_BOUND_ERROR_METHOD = ERB.new(<<~TEMPLATE, trim_mode: "-")
              def self.raise_min_bound_error(input_value, min_bound)
                raise Lutaml::Model::Type::InvalidValueError, "The provided value \#{input_value} is less than the minimum allowed value of \#{min_bound}"
              end
            TEMPLATE

          def to_method_body
            [
              value_for(MAX_BOUND, type: :max),
              value_for(MIN_BOUND, type: :min),
            ].compact.join("\n")
          end

          def to_error_methods
            [
              value_for(MAX_BOUND_ERROR_METHOD, type: :max),
              value_for(MIN_BOUND_ERROR_METHOD, type: :min),
            ].compact.join("\n")
          end

          private

          def value_for(constant, type:)
            return unless send("#{type}_bound_exist?")

            constant.result(binding)
          end

          def min_bound_exist?
            min_inclusive || min_exclusive
          end

          def max_bound_exist?
            max_inclusive || max_exclusive
          end
        end
      end
    end
  end
end
