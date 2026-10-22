# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      class Boolean < Value
        def self.cast(value, _options = EMPTY_OPTIONS)
          return nil if value.nil?
          return value if Utils.uninitialized?(value)
          # Actual booleans are the dominant input (default resolution,
          # parsed JSON/YAML literals): answer without the two to_s +
          # match? allocations the lexical path costs.
          return value if value.equal?(true) || value.equal?(false)
          return true if value.to_s.match?(/^(true|t|yes|y|1)$/i)
          return false if value.to_s.match?(/^(false|f|no|n|0)$/i)

          value
        end

        def self.serialize(value)
          return nil if value.nil?

          !!value
        end

        # Default XSD type for Boolean
        #
        # @return [String] xs:boolean
        def self.default_xsd_type
          "xs:boolean"
        end
      end
    end
  end
end
