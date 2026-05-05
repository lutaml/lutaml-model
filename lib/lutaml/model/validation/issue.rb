# frozen_string_literal: true

module Lutaml
  module Model
    module Validation
      # Serializable validation issue with severity, code, location, and
      # suggestion. Used by Rule#check to report problems and aggregated
      # by LayerResult and Report.
      class Issue < Lutaml::Model::Serializable
        # Allowed severity levels for validation issues.
        SEVERITIES = %w[error warning info notice].freeze

        attribute :severity, :string
        attribute :code, :string
        attribute :message, :string
        attribute :location, :string
        attribute :line, :integer
        attribute :suggestion, :string

        json do
          map "severity", to: :severity
          map "code", to: :code
          map "message", to: :message
          map "location", to: :location
          map "line", to: :line
          map "suggestion", to: :suggestion
        end

        def initialize(attributes = {})
          super
          validate_severity!
        end

        def error?
          severity == "error"
        end

        def warning?
          severity == "warning"
        end

        def info?
          severity == "info"
        end

        def notice?
          severity == "notice"
        end

        private

        def validate_severity!
          return if severity.nil? || SEVERITIES.include?(severity)

          raise ArgumentError,
                "Invalid severity: #{severity}. " \
                "Must be one of: #{SEVERITIES.join(', ')}"
        end
      end
    end
  end
end
