# frozen_string_literal: true

require "json"

# Backward compatibility - delegates to Lutaml::Json::Adapter
# @deprecated Use Lutaml::Json::Adapter::StandardAdapter instead

module Lutaml
  module KeyValue
    module Adapter
      module Json
        class StandardAdapter < Document
          FORMAT_SYMBOL = :json

          def self.parse(json, _options = {})
            JSON.parse(json, create_additions: false)
          end

          # Internal lutaml-model options threaded through by
          # Serialize#to (register, adapter selection) and consumed here
          # (:pretty). JSON.generate raises on unknown keywords (json >= 3),
          # so they must not be forwarded (#767).
          INTERNAL_JSON_OPTIONS = %i[register _adapter_override adapter pretty].freeze

          def to_json(*args)
            options = args.first || {}

            # Handle KeyValueElement input (new symmetric architecture)
            attributes_to_serialize = if @attributes.is_a?(Lutaml::KeyValue::DataModel::Element)
                                        # Unwrap __root__ wrapper to get actual content
                                        @attributes.to_hash["__root__"]
                                      else
                                        # Legacy Hash input (backward compatibility)
                                        @attributes
                                      end

            json_args = args.map do |arg|
              next arg unless arg.is_a?(Hash)

              arg.reject { |key, _| INTERNAL_JSON_OPTIONS.include?(key) }
            end

            if options[:pretty]
              JSON.pretty_generate(attributes_to_serialize, *json_args)
            else
              JSON.generate(attributes_to_serialize, *json_args)
            end
          end
        end
      end
    end
  end
end
