module Lutaml
  module Model
    module Services
      module Type
        class Validator
          class String < Validator
            module ClassMethods
              def validate!(value, options)
                return if Utils.blank?(value)

                validate_values!(value, options[:values])
                validate_length!(value, options)
                validate_pattern!(value, options)
              end

              def validate_length!(value, options)
                min, max = options&.values_at(:min, :max)
                return if min.nil? && max.nil?

                validate_min_length!(value, min) if min
                validate_max_length!(value, max) if max
              end

              def validate_pattern!(value, options)
                pattern = options[:pattern]
                return if Utils.blank?(pattern)
                return if value.match?(pattern)

                raise Lutaml::Model::Type::PatternNotMatchedError.new(value,
                                                                      pattern)
              end

              def validate_min_length!(value, min)
                return if value.length >= min

                raise Lutaml::Model::Type::MinLengthError.new(value, min)
              end

              def validate_max_length!(value, max)
                return if value.length <= max

                raise Lutaml::Model::Type::MaxLengthError.new(value, max)
              end
            end

            extend ClassMethods
            include ClassMethods
          end
        end
      end
    end
  end
end
