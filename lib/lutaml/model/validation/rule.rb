# frozen_string_literal: true

module Lutaml
  module Model
    module Validation
      # Abstract base class for validation rules. Subclass and override
      # {#code}, {#category}, {#severity}, {#applicable?}, and {#check}
      # to implement domain-specific validation logic.
      #
      # Use the private {#issue} helper inside {#check} to create issues
      # that inherit the rule's severity and code by default.
      class Rule
        def code
          nil
        end

        def category
          :general
        end

        def severity
          "error"
        end

        def applicable?(_context)
          true
        end

        def check(_context)
          []
        end

        def needs_deferred?
          false
        end

        def collect(_element, _context); end

        def complete(_context)
          []
        end

        private

        def issue(message, location: nil, line: nil, suggestion: nil,
                  severity: nil, code: nil)
          Issue.new(
            severity: severity || self.severity,
            code: code || self.code,
            message: message,
            location: location,
            line: line,
            suggestion: suggestion,
          )
        end
      end
    end
  end
end
