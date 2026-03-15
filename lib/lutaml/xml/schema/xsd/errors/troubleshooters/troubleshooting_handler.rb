# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      module Xsd
        module Errors
          module Troubleshooters
            # Base class for troubleshooting handlers
            #
            # Troubleshooting handlers provide actionable tips to help users
            # resolve errors.
            #
            # @example Implementing a custom troubleshooter
            #   class MyTroubleshooter < TroubleshootingHandler
            #     def tips_for(error)
            #       [
            #         "Check configuration",
            #         "Verify file paths"
            #       ]
            #     end
            #   end
            #
            # @example Registering a troubleshooter
            #   MyError.use_troubleshooter(MyTroubleshooter)
            class TroubleshootingHandler
              # Generate troubleshooting tips for the given error
              #
              # @param error [EnhancedError] The error to generate tips for
              # @return [Array<String>] List of troubleshooting tips
              # @abstract Subclasses must implement this method
              def tips_for(error)
                raise NotImplementedError,
                      "#{self.class} must implement #tips_for"
              end

              # Generate tips for the error
              #
              # Alias for tips_for to support chain of responsibility pattern
              #
              # @param error [EnhancedError] The error
              # @return [Array<String>] Troubleshooting tips
              def generate_tips(error)
                tips_for(error)
              end

              protected

              # Check if tips can be generated for this error
              #
              # @param error [EnhancedError] The error
              # @return [Boolean] True if tips can be generated
              def can_troubleshoot?(error)
                error.context && !error.context.to_h.empty?
              end

              # Get context from error
              #
              # @param error [EnhancedError] The error
              # @return [ErrorContext, nil] The error context
              def context_from(error)
                error.context
              end
            end
          end
        end
      end
    end
  end
end
