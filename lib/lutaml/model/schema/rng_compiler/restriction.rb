# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module RngCompiler
        # RNG restriction collector. All facet emit + predicate logic lives
        # in Lutaml::Model::Schema::Restriction; only RNG-specific parsing
        # (`<param name="…">`) lives here.
        class Restriction < Lutaml::Model::Schema::Restriction
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

          private

          def numeric_or_string(value)
            return value.to_i if /\A-?\d+\z/.match?(value)
            return value.to_f if /\A-?\d+\.\d+\z/.match?(value)

            value
          end
        end
      end
    end
  end
end
