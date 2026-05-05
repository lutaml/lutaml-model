# frozen_string_literal: true

module Lutaml
  module Model
    module Validation
      class Issue < Lutaml::Model::Serializable
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
      end
    end
  end
end
