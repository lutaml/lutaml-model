require "json"
require_relative "document"

module Lutaml
  module Model
    module Json
      class StandardAdapter < Document
        FORMAT_SYMBOL = :json

        def self.parse(json, _options = {})
          JSON.parse(json, create_additions: false)
        end

        def to_json(*args)
          options = args.first || {}

          # Handle KeyValueElement input (new symmetric architecture)
          attributes_to_serialize = if @attributes.is_a?(Lutaml::Model::KeyValueDataModel::KeyValueElement)
                                      # Unwrap __root__ wrapper to get actual content
                                      @attributes.to_hash["__root__"]
                                    else
                                      # Legacy Hash input (backward compatibility)
                                      @attributes
                                    end

          if options[:pretty]
            JSON.pretty_generate(attributes_to_serialize, *args)
          else
            JSON.generate(attributes_to_serialize, *args)
          end
        end
      end
    end
  end
end
