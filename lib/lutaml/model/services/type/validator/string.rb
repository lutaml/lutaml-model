module Lutaml
  module Model
    module Services
      module Type
        class Validator
          class String < Validator
            module ClassMethods
              def validate!(value, options)
                return if Utils.blank?(value)

                validate_length!(value, options)
                validate_pattern!(value, options)
              end

              def validate_length!(value, options)
                return if Utils.blank?(options)

                validate_min_length!(value, options[:min]) if options[:min]
                validate_max_length!(value, options[:max]) if options[:max]
              end

              def validate_pattern!(value, options)
                return if Utils.blank?(options)
                return if value.match?(options[:pattern])

                raise Lutaml::Model::Type::PatternError.new(value, options[:pattern])
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
