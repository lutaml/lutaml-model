# frozen_string_literal: true

module Lutaml
  module Model
    module Validation
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
