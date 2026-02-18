require "oj"
require_relative "document"

module Lutaml
  module Model
    module Json
      class OjAdapter < Document
        def self.parse(json, _options = {})
          Oj.load(json)
        end

        def to_json(*args)
          # Handle KeyValueElement input (new symmetric architecture)
          attributes_to_serialize = if @attributes.is_a?(Lutaml::Model::KeyValueDataModel::KeyValueElement)
                                      # Unwrap __root__ wrapper to get actual content
                                      @attributes.to_hash["__root__"]
                                    else
                                      # Legacy Hash input (backward compatibility)
                                      @attributes
                                    end

          Oj.dump(attributes_to_serialize, *args)
        end
      end
    end
  end
end
