# frozen_string_literal: true

require_relative "concerns/has_issues"

module Lutaml
  module Model
    module Validation
      class LayerResult < Lutaml::Model::Serializable
        include HasIssues

        attribute :name, :string
        attribute :status, :string
        attribute :duration_ms, :integer
        attribute :issues, Issue, collection: true

        json do
          map "name", to: :name
          map "status", to: :status
          map "duration_ms", to: :duration_ms
          map "issues", to: :issues
        end

        def pass?
          status == "pass"
        end

        def fail?
          status == "fail"
        end
      end
    end
  end
end
