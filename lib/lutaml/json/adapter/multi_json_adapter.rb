# frozen_string_literal: true

# Lazily load multi_json only when actually needed
# This allows the gem to work even if multi_json is not installed
# (as long as the standard JSON library is available)

module Lutaml
  module Json
    module Adapter
      class MultiJsonAdapter < Document
        def self.parse(json, _options = {})
          require "multi_json"
          MultiJson.load(json)
        rescue LoadError
          raise LoadError,
                "multi_json gem is not available. Please add 'multi_json' to your Gemfile."
        end

        def to_json(*)
          require "multi_json"
          # Handle KeyValueElement input (new symmetric architecture)
          attributes_to_serialize = if @attributes.is_a?(Lutaml::KeyValue::DataModel::Element)
                                      # Unwrap __root__ wrapper to get actual content
                                      @attributes.to_hash["__root__"]
                                    else
                                      # Legacy Hash input (backward compatibility)
                                      @attributes
                                    end

          MultiJson.dump(attributes_to_serialize, *)
        rescue LoadError
          raise LoadError,
                "multi_json gem is not available. Please add 'multi_json' to your Gemfile."
        end
      end
    end
  end
end
