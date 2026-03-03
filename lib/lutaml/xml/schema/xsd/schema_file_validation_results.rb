# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        # Collection of file validation results for schema validation command
        class SchemaFileValidationResults
          attr_reader :file_results

          # @param file_results [Array<FileValidationResult>] Array of file validation results
          def initialize(file_results)
            @file_results = file_results
          end

          # @return [Array<FileValidationResult>] Files that failed validation
          def failed_files
            file_results.select(&:failure?)
          end

          # @return [Array<FileValidationResult>] Files that passed validation
          def valid_files
            file_results.select(&:success?)
          end

          # @return [Integer] Total number of files validated
          def total_count
            file_results.size
          end

          # @return [Integer] Number of valid files
          def valid_count
            valid_files.size
          end

          # @return [Integer] Number of invalid files
          def invalid_count
            failed_files.size
          end

          # Convert to hash for formatters
          # @return [Hash] Hash representation with files and counts
          def to_h
            {
              files: file_results.map(&:to_h),
              total: total_count,
              valid: valid_count,
              invalid: invalid_count,
            }
          end
        end
      end
    end
  end
end
