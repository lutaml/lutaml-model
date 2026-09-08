# frozen_string_literal: true

# Lazily load oj only when actually needed
# This allows the gem to work even if oj is not installed
# (as long as the standard JSON library is available)

module Lutaml
  module Json
    module Adapter
      class OjAdapter < Document
        def self.parse(json, _options = {})
          require "oj"
          Oj.load(json)
        rescue LoadError
          raise LoadError,
                "oj gem is not available. Please add 'oj' to your Gemfile or use the StandardAdapter."
        end

        # rubocop:disable Style/ArgumentsForwarding -- anonymous * requires Ruby 3.2+
        # Oj has its own option namespace and its own escape_mode. Handing it
        # the stdlib generator's options overrides that configuration, so it
        # takes none of them -- which is what it received before.
        def ignores_generator_options?
          true
        end

        def to_json(*args)
          require "oj"
          # Handle KeyValueElement input (new symmetric architecture)
          attributes_to_serialize = if @attributes.is_a?(Lutaml::KeyValue::DataModel::Element)
                                      # Unwrap __root__ wrapper to get actual content
                                      @attributes.to_hash["__root__"]
                                    else
                                      # Legacy Hash input (backward compatibility)
                                      @attributes
                                    end

          Oj.dump(attributes_to_serialize, *args)
        # rubocop:enable Style/ArgumentsForwarding
        rescue LoadError
          raise LoadError,
                "oj gem is not available. Please add 'oj' to your Gemfile or use the StandardAdapter."
        end
      end
    end
  end
end
