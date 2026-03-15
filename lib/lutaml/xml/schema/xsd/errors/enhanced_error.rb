# frozen_string_literal: true

require_relative "error_context"
require_relative "message_builder"

module Lutaml
  module Xml
    module Schema
      module Xsd
        module Errors
          # Base class for enhanced errors with rich contextual information
          #
          # @example Creating an enhanced error
          #   error = EnhancedError.new(
          #     "Type not found",
          #     context: {
          #       location: "/root/element",
          #       actual_value: "MyType",
          #       repository: schema_repository
          #     }
          #   )
          #
          # @example Getting suggestions
          #   error.suggestions # => [Suggestion, ...]
          #
          # @example Getting troubleshooting tips
          #   error.troubleshooting_tips # => ["Check namespace...", ...]
          class EnhancedError < StandardError
            # @return [ErrorContext] Error context
            attr_reader :context

            # Initialize enhanced error
            #
            # @param message [String] Error message
            # @param context [Hash, ErrorContext] Error context
            def initialize(message, context: {})
              super(message)
              @context = context.is_a?(ErrorContext) ? context : ErrorContext.new(context)
              @suggester = nil
              @troubleshooter = nil
            end

            # Get error suggestions
            #
            # @return [Array<Suggestion>] List of suggestions
            def suggestions
              return [] unless suggester

              @suggestions ||= suggester.generate_suggestions(self)
            end

            # Get troubleshooting tips
            #
            # @return [Array<String>] List of troubleshooting tips
            def troubleshooting_tips
              return [] unless troubleshooter

              @troubleshooting_tips ||= troubleshooter.generate_tips(self)
            end

            # Build detailed error message with context, suggestions, and tips
            #
            # @return [String] Detailed error message
            def to_detailed_message
              MessageBuilder.new(self).build
            end

            # Get error code
            #
            # @return [String] Error code
            def error_code
              "E000"
            end

            # Get error severity
            #
            # @return [Symbol] Error severity (:error, :warning, :info)
            def severity
              :error
            end

            private

            # Get suggester for this error type
            #
            # @return [Object, nil] Suggester instance
            def suggester
              return @suggester if defined?(@suggester)

              @suggester = self.class.suggester_class&.new
            end

            # Get troubleshooter for this error type
            #
            # @return [Object, nil] Troubleshooter instance
            def troubleshooter
              return @troubleshooter if defined?(@troubleshooter)

              @troubleshooter = self.class.troubleshooter_class&.new
            end

            class << self
              # Get suggester class for this error type
              #
              # @return [Class, nil] Suggester class
              attr_accessor :suggester_class

              # Set suggester class for this error type
              #
              # @param klass [Class] Suggester class

              # Get troubleshooter class for this error type
              #
              # @return [Class, nil] Troubleshooter class
              attr_accessor :troubleshooter_class

              # Set troubleshooter class for this error type
              #
              # @param klass [Class] Troubleshooter class

              # Register suggester for this error type
              #
              # @param klass [Class] Suggester class
              # @return [void]
              def use_suggester(klass)
                self.suggester_class = klass
              end

              # Register troubleshooter for this error type
              #
              # @param klass [Class] Troubleshooter class
              # @return [void]
              def use_troubleshooter(klass)
                self.troubleshooter_class = klass
              end
            end
          end
        end
      end
    end
  end
end
