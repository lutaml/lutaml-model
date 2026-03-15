# frozen_string_literal: true

# Lazily load toml-rb only when actually needed
# This allows the gem to work even if toml-rb is not installed
# (as long as tomlib is available as an alternative)

module Lutaml
  module KeyValue
    module Adapter
      module Toml
        class TomlRbAdapter < Document
          def self.parse(toml, _options = {})
            require "toml-rb"
            TomlRB.parse(toml)
          rescue LoadError
            raise LoadError,
                  "toml-rb gem is not available. Please add 'toml-rb' to your Gemfile or use tomlib adapter."
          end

          def to_toml(*)
            require "toml-rb"
            # Handle KeyValueElement input (new symmetric architecture)
            attributes_to_serialize = if @attributes.is_a?(Lutaml::KeyValue::DataModel::Element)
                                        # Unwrap __root__ wrapper to get actual content
                                        @attributes.to_hash["__root__"]
                                      else
                                        # Legacy Hash input (backward compatibility)
                                        @attributes
                                      end

            TomlRB.dump(attributes_to_serialize)
          rescue LoadError
            raise LoadError,
                  "toml-rb gem is not available. Please add 'toml-rb' to your Gemfile or use tomlib adapter."
          end
        end
      end
    end
  end
end
