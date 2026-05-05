# frozen_string_literal: true

module Lutaml
  module Model
    module Validation
      # Abstract base class for validation remediation. Subclass and
      # override {#id}, {#targets}, {#applicable?}, {#fix}, and
      # {#preview} to implement auto-fix logic for specific issue codes.
      class Remediation
        def id
          nil
        end

        def targets
          nil
        end

        def applicable?(_context, _report)
          true
        end

        def fix(_context, _report)
          RemediationResult.new(success: false, message: "Not implemented")
        end

        def preview(_context, _report)
          nil
        end
      end
    end
  end
end
