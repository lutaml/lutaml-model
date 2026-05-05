# frozen_string_literal: true

require "time"
require_relative "issue"
require_relative "layer_result"

module Lutaml
  module Model
    module Validation
      class Report < Lutaml::Model::Serializable
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

        def all_issues
          layers.flat_map(&:issues)
        end

        def all_errors
          all_issues.select(&:error?)
        end

        def all_warnings
          all_issues.select(&:warning?)
        end

        def all_infos
          all_issues.select(&:info?)
        end

        def all_notices
          all_issues.select(&:notice?)
        end
      end
    end
  end
end
