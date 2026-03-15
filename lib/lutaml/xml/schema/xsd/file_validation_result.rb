# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        # Value object representing the validation result for a single file
        class FileValidationResult
          attr_reader :file, :error, :detected_version

          # @param file [String] Path to the validated file
          # @param valid [Boolean] Whether the file is valid
          # @param error [String, nil] Error message if validation failed
          # @param detected_version [String, nil] Detected XSD version (1.0 or 1.1)
          def initialize(file:, valid:, error: nil, detected_version: nil)
            @file = file
            @valid = valid
            @error = error
            @detected_version = detected_version
          end

          # @return [Boolean] true if the file passed validation
          def success?
            @valid
          end

          # @return [Boolean] true if the file failed validation
          def failure?
            !success?
          end

          # Convert to hash for backward compatibility
          # @return [Hash] Hash representation of the result
          def to_h
            {
              file: file,
              valid: success?,
              error: error,
              detected_version: detected_version,
            }.compact
          end

          # @return [String] Human-readable string representation
          def to_s
            if success?
              "#{file}: VALID"
            else
              "#{file}: INVALID - #{error}"
            end
          end
        end
      end
    end
  end
end
