# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        # Base error class for lutaml-xsd errors
        class Error < StandardError; end

        # Schema not found with helpful context
        class SchemaNotFoundError < Error
          attr_reader :location, :searched_paths, :suggestions

          def initialize(location:, searched_paths: [], suggestions: [])
            @location = location
            @searched_paths = searched_paths
            @suggestions = suggestions

            message = build_message
            super(message)
          end

          private

          def build_message
            msg = "Schema not found: #{@location}\n\n"

            if @searched_paths.any?
              msg += "Searched in:\n"
              @searched_paths.each { |path| msg += "  - #{path}\n" }
              msg += "\n"
            end

            if @suggestions.any?
              msg += "Did you mean one of these?\n"
              @suggestions.each { |s| msg += "  - #{s}\n" }
              msg += "\n"
            end

            msg += "💡 See: https://www.lutaml.org/lutaml-xsd/troubleshooting/schema-not-found"
            msg
          end
        end

        # Type not found with resolution path
        class TypeNotFoundError < Error
          attr_reader :qualified_name, :resolution_path, :available_namespaces

          def initialize(qualified_name:, resolution_path: [],
      available_namespaces: [])
            @qualified_name = qualified_name
            @resolution_path = resolution_path
            @available_namespaces = available_namespaces

            message = build_message
            super(message)
          end

          private

          def build_message
            msg = "Type not found: #{@qualified_name}\n\n"

            if @resolution_path.any?
              msg += "Resolution path:\n"
              @resolution_path.each_with_index do |step, i|
                msg += "  #{i + 1}. #{step}\n"
              end
              msg += "\n"
            end

            if @available_namespaces.any?
              msg += "Available namespaces:\n"
              @available_namespaces.first(5).each { |ns| msg += "  - #{ns}\n" }
              msg += "  ... and #{@available_namespaces.size - 5} more\n" if @available_namespaces.size > 5
              msg += "\n"
            end

            msg += "💡 See: https://www.lutaml.org/lutaml-xsd/troubleshooting/type-not-found"
            msg
          end
        end

        # Package validation error
        class PackageValidationError < Error; end

        # Configuration error
        class ConfigurationError < Error; end

        # Schema validation error (pre-parsing validation)
        class SchemaValidationError < Error; end

        # Validation failed error with structured result
        class ValidationFailedError < Error
          attr_reader :validation_result

          # @param validation_result [ValidationResult] The validation result
          def initialize(validation_result)
            @validation_result = validation_result
            super(validation_result.to_s)
          end

          # Get all error messages
          # @return [Array<String>]
          def error_messages
            @validation_result.error_messages
          end

          # Get errors for specific field
          # @param field [Symbol, String] Field name
          # @return [Array<ValidationError>]
          def errors_for(field)
            @validation_result.errors_for(field)
          end
        end

        # Package merge error with structured conflict report
        class PackageMergeError < Error
          attr_reader :conflict_report, :error_strategy_sources

          def initialize(message:, conflict_report:, error_strategy_sources: [])
            @conflict_report = conflict_report
            @error_strategy_sources = error_strategy_sources

            full_message = build_message(message)
            super(full_message)
          end

          private

          def build_message(message)
            lines = [message, "", @conflict_report.to_s]

            if @error_strategy_sources.any?
              lines << ""
              lines << "Packages using 'error' strategy:"
              @error_strategy_sources.each do |source|
                lines << "  - #{source.package_path}"
              end
            end

            lines.join("\n")
          end
        end
      end
    end
  end
end
