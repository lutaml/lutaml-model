# frozen_string_literal: true

require "json"
require_relative "../../../json/generator_options"

# Backward compatibility - delegates to Lutaml::Json::Adapter
# @deprecated Use Lutaml::Json::Adapter::StandardAdapter instead

module Lutaml
  module KeyValue
    module Adapter
      module Json
        class StandardAdapter < Document
          FORMAT_SYMBOL = :json

          def self.parse(json, _options = {})
            JSON.parse(json)
          end

          # This adapter hands its payload to the stdlib generator, so a
          # JSON::State carrying the outer formatting is meaningful here.
          def accepts_generator_state?
            true
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

            unless Lutaml::Json::GeneratorOptions.lutaml_options?(args.first)
              return attributes_to_serialize.to_json(*args)
            end

            options = args.first || {}
            generator_options = Lutaml::Json::GeneratorOptions.filter(options)

            if options[:pretty]
              JSON.pretty_generate(attributes_to_serialize, generator_options)
            else
              JSON.generate(attributes_to_serialize, generator_options)
            end
          end
        end
      end
    end
  end
end
