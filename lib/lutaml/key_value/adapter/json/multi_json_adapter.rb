# frozen_string_literal: true

require "multi_json"

module Lutaml
  module KeyValue
    module Adapter
      module Json
        class MultiJsonAdapter < Document
          def self.parse(json, _options = {})
            MultiJson.load(json)
          end

          def to_json(*args)
            # Handle KeyValueElement input (new symmetric architecture)
            attributes_to_serialize = if @attributes.is_a?(Lutaml::KeyValue::DataModel::Element)
                                        # Unwrap __root__ wrapper to get actual content
                                        @attributes.to_hash["__root__"]
                                      else
                                        # Legacy Hash input (backward compatibility)
                                        @attributes
                                      end

            MultiJson.dump(attributes_to_serialize, *args)
          end
        end
      end
    end
  end
end
