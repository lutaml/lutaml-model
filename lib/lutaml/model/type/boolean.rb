# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      class Boolean < Value
        def self.cast(value, _options = {})
          return nil if value.nil?
          return value if Utils.uninitialized?(value)
          return true if value == true || value.to_s.match?(/^(true|t|yes|y|1)$/i)
          return false if value == false || value.to_s.match?(/^(false|f|no|n|0)$/i)

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
