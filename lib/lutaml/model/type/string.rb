# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      class String < Value
        # Performance-optimized cast with short-circuit for already-correct types
        def self.cast(value, options = {})
          return nil if value.nil?
          return value if Utils.uninitialized?(value)
          # Short-circuit: return immediately if already a String with no options
          # Use identity check for EMPTY_OPTIONS (faster than .empty?)
          if value.is_a?(::String) && options.equal?(EMPTY_OPTIONS)
            return value
          end

          value = value.to_s
          unless options.equal?(EMPTY_OPTIONS)
            Model::Services::Type::Validator::String.validate!(value,
                                                               options)
          end
          value
        end

        # Default XSD type for String
        #
        # @return [String] xs:string
        def self.default_xsd_type
          "xs:string"
        end
      end
    end
  end
end
