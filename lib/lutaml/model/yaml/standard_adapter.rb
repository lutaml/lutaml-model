require "yaml"
require_relative "document"

module Lutaml
  module Model
    module Yaml
      class StandardAdapter < Document
        FORMAT_SYMBOL = :yaml
        PERMITTED_CLASSES_BASE = [Date, Time, DateTime, Symbol, Hash,
                                  Array].freeze

        PERMITTED_CLASSES = if defined?(BigDecimal)
                              PERMITTED_CLASSES_BASE + [BigDecimal]
                            else
                              PERMITTED_CLASSES_BASE
                            end.freeze

        def self.parse(yaml, _options = {})
          YAML.safe_load(yaml, permitted_classes: PERMITTED_CLASSES)
        end

        def to_yaml(options = {})
          YAML.dump(@attributes, options)
        end
      end
    end
  end
end
