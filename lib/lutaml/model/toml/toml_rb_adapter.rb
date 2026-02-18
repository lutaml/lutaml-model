require "toml-rb"
require_relative "document"

module Lutaml
  module Model
    module Toml
      class TomlRbAdapter < Document
        def self.parse(toml, _options = {})
          TomlRB.parse(toml)
        end

        def to_toml(*)
          # Handle KeyValueElement input (new symmetric architecture)
          attributes_to_serialize = if @attributes.is_a?(Lutaml::Model::KeyValueDataModel::KeyValueElement)
                                      # Unwrap __root__ wrapper to get actual content
                                      @attributes.to_hash["__root__"]
                                    else
                                      # Legacy Hash input (backward compatibility)
                                      @attributes
                                    end

          TomlRB.dump(attributes_to_serialize)
        end
      end
    end
  end
end
