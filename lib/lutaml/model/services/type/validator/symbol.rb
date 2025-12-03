module Lutaml
  module Model
    module Services
      module Type
        class Validator
          class Symbol < String
            module ClassMethods
              def validate!(value, options)
                return if Utils.blank?(value)

                # Convert string to symbol for validation if values are symbols
                validated_value = value
                if options[:values]&.first.is_a?(::Symbol)
                  validated_value = value.to_sym
                end

                validate_values!(validated_value, options[:values])
                validate_length!(value, options)
                validate_pattern!(value, options)
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
