# frozen_string_literal: true

# Lazily load multi_json only when actually needed
# This allows the gem to work even if multi_json is not installed
# (as long as the standard JSON library is available)

require_relative "../generator_options"

module Lutaml
  module Json
    module Adapter
      class MultiJsonAdapter < Document
        def self.parse(json, _options = {})
          require "multi_json"
          # multi_json 1.21.1 hardcodes create_additions and quirks_mode as
          # load defaults; json 3.0 removed both, so its json_gem backend
          # raises. That backend IS JSON.parse, so calling it directly is
          # equivalent. Remove once multi_json ships a json 3 fix.
          return JSON.parse(json) if multi_json_load_broken?

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

          unless GeneratorOptions.lutaml_options?(args.first)
            return attributes_to_serialize.to_json(*args)
          end

          MultiJson.dump(attributes_to_serialize, dump_options(args.first))
        rescue LoadError
          raise LoadError,
                "multi_json gem is not available. Please add 'multi_json' to your Gemfile."
        end

        # multi_json 1.21.1 passes create_additions and quirks_mode on every
        # load; json 3.0 removed both, so its json_gem backend raises. Detect
        # the OPTIONS the backend will send rather than naming the backend, so
        # this stops firing by itself once multi_json ships a fix.
        REMOVED_BY_JSON_3 = %i[create_additions quirks_mode].freeze

        def self.multi_json_load_broken?
          return false if ::Gem::Version.new(::JSON::VERSION) < ::Gem::Version.new("3.0.0")

          load_options = ::MultiJson.adapter.load_options
          load_options.is_a?(::Hash) &&
            load_options.keys.intersect?(REMOVED_BY_JSON_3)
        rescue ::StandardError
          false
        end
        private_class_method :multi_json_load_broken?

        private

        # MultiJson forwards options to whichever backend is active, and each
        # backend has its own option names (Oj takes :omit_nil). Strip only
        # LutaML's own keys here -- filtering through the stdlib JSON
        # allowlist would discard legitimate backend options.
        def dump_options(options)
          GeneratorOptions.strip_internal(options)
        end
      end
    end
  end
end
