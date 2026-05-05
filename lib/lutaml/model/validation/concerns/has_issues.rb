# frozen_string_literal: true

module Lutaml
  module Model
    module Validation
      # Shared severity filtering for objects that expose an `issues`
      # collection. Included by LayerResult and Report.
      module HasIssues
        def errors
          issues.select(&:error?)
        end

        def warnings
          issues.select(&:warning?)
        end

        def infos
          issues.select(&:info?)
        end

        def notices
          issues.select(&:notice?)
        end
      end
    end
  end
end
