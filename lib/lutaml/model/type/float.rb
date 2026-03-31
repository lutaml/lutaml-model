# frozen_string_literal: true

module Lutaml
  module Model
    module Type
      class Float < Value
        def self.cast(value, options = {})
          return nil if value.nil?
          return value if Utils.uninitialized?(value)

          # Use identity check for EMPTY_OPTIONS (faster than .empty?)
          unless options.equal?(EMPTY_OPTIONS)
            Model::Services::Type::Validator::Number.validate!(value, options)
          end
          value.to_f
        end

        def self.serialize(value)
          return nil if value.nil?

          cast(value)
        end

        # XSD type for Float
        #
        # @return [String] xs:float
        def self.default_xsd_type
          "xs:float"
        end
      end
    end
  end
end
