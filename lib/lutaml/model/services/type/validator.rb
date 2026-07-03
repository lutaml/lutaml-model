# frozen_string_literal: true

module Lutaml
  module Model
    module Services
      module Type
        class Validator
          autoload :String, "#{__dir__}/validator/string"
          autoload :Symbol, "#{__dir__}/validator/symbol"
          autoload :Number, "#{__dir__}/validator/number"

          module ClassMethods
            def validate_values!(value, values)
              return if Utils.blank?(values) || values.include?(value)

              raise Lutaml::Model::Type::InvalidValueError.new(value, values)
            end

            def validate_min_max_bounds!(value, options)
              min, max = options&.values_at(:min, :max)
              return if min.nil? && max.nil?

              validate_min_bound!(value, min) if min
              validate_max_bound!(value, max) if max
            end

            def validate_min_bound!(value, min)
              return if value >= min

              raise Lutaml::Model::Type::MinBoundError.new(value, min)
            end

            def validate_max_bound!(value, max)
              return if value <= max

              raise Lutaml::Model::Type::MaxBoundError.new(value, max)
            end

            # Reads the canonical facet keys (:min_exclusive/:max_exclusive);
            # the inclusive `validate_min_max_bounds!` above reads the legacy
            # :min/:max keys it shares with the eager cast path.
            def validate_exclusive_bounds!(value, options)
              min, max = options&.values_at(:min_exclusive, :max_exclusive)
              return if min.nil? && max.nil?

              validate_min_exclusive_bound!(value, min) if min
              validate_max_exclusive_bound!(value, max) if max
            end

            def validate_min_exclusive_bound!(value, min)
              return if value > min

              raise Lutaml::Model::Type::MinExclusiveError.new(value, min)
            end

            def validate_max_exclusive_bound!(value, max)
              return if value < max

              raise Lutaml::Model::Type::MaxExclusiveError.new(value, max)
            end
          end

          extend ClassMethods
          include ClassMethods
        end
      end
    end
  end
end
