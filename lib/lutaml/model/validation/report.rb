# frozen_string_literal: true

require "time"
require_relative "concerns/has_issues"
require_relative "issue"
require_relative "layer_result"

module Lutaml
  module Model
    module Validation
      class Report < Lutaml::Model::Serializable
        include HasIssues

        attribute :source, :string
        attribute :timestamp, :string
        attribute :valid, :boolean
        attribute :duration_ms, :integer
        attribute :layers, LayerResult, collection: true

        json do
          map "source", to: :source
          map "timestamp", to: :timestamp
          map "valid", to: :valid
          map "duration_ms", to: :duration_ms
          map "layers", to: :layers
        end

        def initialize(attributes = {})
          super
          self.timestamp ||= Time.now.utc.iso8601
        end

        def issues
          layers ? layers.flat_map(&:issues) : []
        end
      end
    end
  end
end
