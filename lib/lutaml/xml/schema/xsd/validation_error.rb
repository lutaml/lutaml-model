# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        # Represents a single validation error with structured information
        class ValidationError < Lutaml::Model::Serializable
          attribute :field, :string
          attribute :message, :string
          attribute :value, :string
          attribute :constraint, :string

          yaml do
            map "field", to: :field
            map "message", to: :message
            map "value", to: :value
            map "constraint", to: :constraint
          end

          # Factory method for creating validation errors with type conversion
          # @param field [Symbol, String] The field that failed validation
          # @param message [String] Human-readable error message
          # @param value [Object] The actual value that was invalid (optional)
          # @param constraint [String] The constraint that was violated (optional)
          # @return [ValidationError]
          def self.create(field:, message:, value: nil, constraint: nil)
            new(
              field: field.to_s,
              message: message,
              value: value&.to_s,
              constraint: constraint,
            )
          end

          # Format as human-readable string
          # @return [String]
          def to_s
            parts = ["#{field}: #{message}"]
            parts << "(value: #{value})" if value
            parts << "[constraint: #{constraint}]" if constraint
            parts.join(" ")
          end
        end
      end
    end
  end
end
