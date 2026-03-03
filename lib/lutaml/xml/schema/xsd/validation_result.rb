# frozen_string_literal: true

require_relative "validation_error"
require_relative "errors"

module Lutaml
  module Xml
    module Schema
      module Xsd
        # Result of validation with error collection
        class ValidationResult < Lutaml::Model::Serializable
          attribute :valid, Lutaml::Model::Type::Boolean
          attribute :errors, ValidationError, collection: true

          yaml do
            map "valid", to: :valid
            map "errors", to: :errors
          end

          # Create success result
          # @return [ValidationResult]
          def self.success
            new(valid: true, errors: [])
          end

          # Create failure result with errors
          # @param errors [Array<ValidationError>] Validation errors
          # @return [ValidationResult]
          def self.failure(errors)
            new(valid: false, errors: errors)
          end

          # Check if validation passed
          # @return [Boolean]
          def valid?
            valid
          end

          # Check if validation failed
          # @return [Boolean]
          def invalid?
            !valid
          end

          # Get error count
          # @return [Integer]
          def error_count
            (errors || []).size
          end

          # Get all error messages
          # @return [Array<String>]
          def error_messages
            (errors || []).map(&:message)
          end

          # Get errors for specific field
          # @param field [Symbol, String] Field name
          # @return [Array<ValidationError>]
          def errors_for(field)
            field_str = field.to_s
            (errors || []).select { |e| e.field == field_str }
          end

          # Format as human-readable string
          # @return [String]
          def to_s
            return "Valid" if valid?

            lines = ["Validation failed with #{error_count} error(s):"]
            errors.each_with_index do |error, idx|
              lines << "  #{idx + 1}. #{error}"
            end
            lines.join("\n")
          end

          # Raise error if validation failed
          # @raise [ValidationFailedError]
          def validate!
            raise ValidationFailedError.new(self) if invalid?
          end
        end
      end
    end
  end
end
