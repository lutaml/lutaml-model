# frozen_string_literal: true

module Lutaml
  module Model
    module Services
      module Type
        class Validator
          class Number < Validator
            module ClassMethods
              def validate!(value, options)
                return if Utils.blank?(options)

                validate_values!(value, options[:values])
                validate_min_max_bounds!(value, options)
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
