module Lutaml
  module Model
    module Type
      class Integer < Value
        def self.cast(value)
          return nil if value.nil?
          return 1 if value === true
          return 0 if value === false

          value = case value
                  when ::String
                    if value.match?(/^0[0-7]+$/) # Octal
                      value.to_i(8)
                    elsif value.match?(/^-?\d+(\.\d+)?(e-?\d+)?$/i) # Float/exponential
                      Float(value).to_i
                    else
                      begin
                        Integer(value, 10)
                      rescue StandardError
                        nil
                      end
                    end
                  else
                    begin
                      Integer(value)
                    rescue StandardError
                      nil
                    end
                  end

          validate_values!(value) if values_available?
          validate_min_max_bounds!(value) if min_max_bounds_available?
          value
        end

        # Override serialize to return Integer instead of String
        def self.serialize(value)
          return nil if value.nil?

          cast(value)
        end

        def self.values_available?
          Utils.present?(@values)
        end

        def self.values
          @values
        end

        def self.min_max_bounds_available?
          Utils.present?(min_max_bounds)
        end

        def self.min_max_bounds
          @min_max_bounds
        end

        def self.validate_values!(value)
          raise Lutaml::Model::InvalidValueError.new(name, value, values) unless values.include?(value)
        end

        def self.validate_min_bound!(value)
          raise Lutaml::Model::MinBoundError.new(value, min_max_bounds[:min]) if value < min_max_bounds[:min]
        end

        def self.validate_max_bound!(value)
          raise Lutaml::Model::MaxBoundError.new(value, min_max_bounds[:max]) if value > min_max_bounds[:max]
        end

        def self.validate_min_max_bounds!(value)
          validate_min_bound!(value) if min_max_bounds[:min]
          validate_max_bound!(value) if min_max_bounds[:max]
        end
      end
    end
  end
end
