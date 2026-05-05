# frozen_string_literal: true

require_relative "issue"

module Lutaml
  module Model
    module Validation
      class LayerResult < Lutaml::Model::Serializable
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
