# frozen_string_literal: true

require "date"
require "yaml"

module Lutaml
  module KeyValue
    module Adapter
      module Yaml
        class StandardAdapter < Document
          FORMAT_SYMBOL = :yaml
          PERMITTED_CLASSES_BASE = [Date, Time, DateTime, Symbol, ::Hash,
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
            # Handle KeyValueElement input (new symmetric architecture)
            attributes_to_serialize = @attributes

            YAML.dump(attributes_to_serialize, options)
          end
        end
      end
    end
  end
end
