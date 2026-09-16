# frozen_string_literal: true

require_relative "standard_adapter"

module Lutaml
  module Yaml
    module Adapter
      # YAML over the yeptris engine (libyeptris C11). Uses the native
      # Yeptris::YAML surface, which does not rebind or interact with the
      # Psych constant, so it coexists with the standard adapter in one
      # process. Inherits the document/generation contract; only the
      # engine calls differ.
      #
      # Semantic notes vs the standard adapter's Psych.safe_load:
      # implicit typing is parity-verified (compat_11 schema); anchors
      # and aliases always resolve; a tagged value without a core type
      # materializes as plain data instead of raising DisallowedClass.
      class YeptrisAdapter < StandardAdapter
        # yeptris is required lazily: the ruby-platform variant installs
        # everywhere but only loads where libyeptris exists (no Windows
        # prebuilts) — a broken install must degrade to detection
        # fallback, never crash loads.
        def self.parse(yaml, _options = {})
          require "yeptris"
          require "yeptris/yaml"
          # rubocop:disable-next Naming/VariableNumber -- upstream schema literal
          Yeptris::YAML.load(yaml, schema: :compat_11)
        end

        def to_yaml(_options = {})
          attributes_to_serialize = if @attributes.is_a?(Lutaml::KeyValue::DataModel::Element)
                                      # Unwrap __root__ wrapper to get actual content
                                      @attributes.to_hash["__root__"]
                                    else
                                      # Legacy Hash input (backward compatibility)
                                      @attributes
                                    end

          # Generation must match the standard (Psych) adapter's output
          # byte-for-byte: document separator, quoting of digit-leading
          # strings, flow styles. The neutral Yeptris::YAML.dump is
          # deliberately headerless, so parity goes through the
          # Psych-compatible face of the same engine.
          require "yeptris/psych"
          Yeptris::Psych.dump(attributes_to_serialize)
        end
      end
    end
  end
end
