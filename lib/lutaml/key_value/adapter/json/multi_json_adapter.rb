# frozen_string_literal: true

# Backward compatibility - delegates to Lutaml::Json::Adapter
# @deprecated Use Lutaml::Json::Adapter::MultiJsonAdapter instead

# Lazily load multi_json only when actually needed
# This allows the gem to work even if multi_json is not installed
# (as long as the standard JSON library is available)

require_relative "../../../json/generator_options"

module Lutaml
  module KeyValue
    module Adapter
      module Json
        class MultiJsonAdapter < Document
          def self.parse(json, _options = {})
            require "multi_json"
            MultiJson.load(json)
          rescue LoadError
            raise LoadError,
                  "multi_json gem is not available. Please add 'multi_json' to your Gemfile."
          end

          def to_json(*args)
            require "multi_json"
            # Handle KeyValueElement input (new symmetric architecture)
            attributes_to_serialize = if @attributes.is_a?(Lutaml::KeyValue::DataModel::Element)
                                        # Unwrap __root__ wrapper to get actual content
                                        @attributes.to_hash["__root__"]
                                      else
                                        # Legacy Hash input (backward compatibility)
                                        @attributes
                                      end

            unless Lutaml::Json::GeneratorOptions.lutaml_options?(args.first)
              return attributes_to_serialize.to_json(*args)
            end

            MultiJson.dump(attributes_to_serialize, dump_options(args.first))
          rescue LoadError
            raise LoadError,
                  "multi_json gem is not available. Please add 'multi_json' to your Gemfile."
          end

          private

          # json 3.0 raises ArgumentError on unknown generator options, so
          # LutaML's own options are stripped before reaching the engine.
          # :pretty is MultiJson's own and is kept. :adapter is not
          # sliced here: FormatConversion#to deletes it before the adapter runs.
          def dump_options(options)
            options = {} unless options.is_a?(::Hash)

            Lutaml::Json::GeneratorOptions
              .filter(options)
              .merge(options.slice(:pretty))
          end
        end
      end
    end
  end
end
