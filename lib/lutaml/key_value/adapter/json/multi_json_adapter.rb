# frozen_string_literal: true

# Backward compatibility - delegates to Lutaml::Json::Adapter
# @deprecated Use Lutaml::Json::Adapter::MultiJsonAdapter instead

# Lazily load multi_json only when actually needed
# This allows the gem to work even if multi_json is not installed
# (as long as the standard JSON library is available)

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

          INTERNAL_LUTAML_KEYS = %i[register adapter _adapter_override].freeze

          # rubocop:disable Style/ArgumentsForwarding -- anonymous * requires Ruby 3.2+
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

            # LutaML's own options must not reach the backend: the json
            # gem 3.x and Oj both raise on unknown generator options
            # (multi_json's backend choice shifts with the resolved json
            # version), unlike json 2.x which ignored them.
            # LutaML's own threading keys must not reach the backend; the
            # rest (e.g. :pretty) are meaningful to multi_json. The json
            # gem 3.x and Oj raise on unknown generator options, unlike
            # json 2.x which ignored them.
            dump_args = args.map do |arg|
              next arg unless arg.is_a?(::Hash)

              arg.except(*INTERNAL_LUTAML_KEYS)
            end
            MultiJson.dump(attributes_to_serialize, *dump_args)
          # rubocop:enable Style/ArgumentsForwarding
          rescue LoadError
            raise LoadError,
                  "multi_json gem is not available. Please add 'multi_json' to your Gemfile."
          end
        end
      end
    end
  end
end
