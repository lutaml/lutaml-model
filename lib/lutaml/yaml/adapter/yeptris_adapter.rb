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
      # materializes as plain data instead of raising DisallowedClass;
      # parse failures surface as Psych::SyntaxError like the standard
      # adapter's (the engine's own ParseError is re-raised under the
      # standard class).
      class YeptrisAdapter < StandardAdapter
        # yeptris is required lazily: the ruby-platform variant installs
        # everywhere but only loads where libyeptris exists (no Windows
        # prebuilts) — a broken install must degrade to detection
        # fallback, never crash loads.
        def self.parse(yaml, _options = {})
          require_engine
          require "yeptris/yaml"
          # rubocop:disable-next Naming/VariableNumber -- upstream schema literal
          Yeptris::YAML.load(yaml, schema: :compat_11)
        rescue Yeptris::ParseError => e
          raise syntax_error(e)
        end

        # The engine require sits outside parse's rescue so a broken
        # install still surfaces its LoadError (the detection fallback's
        # contract) instead of a NameError from the rescue clause.
        def self.require_engine
          require "yeptris"
        end
        private_class_method :require_engine

        # The parse-error contract is the standard adapter's: invalid
        # input raises Psych::SyntaxError regardless of the engine, so
        # consumers' rescue ladders (and this gem's own
        # format_error_types conversion to InvalidFormatError) hold on
        # every adapter. The C parser reports the position inside the
        # error message ("... at line L, column C"); lift it into the
        # structured fields. Without psych (Opal) the engine error
        # propagates unchanged.
        def self.syntax_error(error)
          return error unless defined?(::Psych::SyntaxError)

          match = /\bline (\d+),? column (\d+)/.match(error.message)
          line = match ? match[1].to_i : 0
          column = match ? match[2].to_i : 0
          problem = error.message.sub(/\s+at\s+line\s+\d+,?\s+column\s+\d+\z/, "")
          ::Psych::SyntaxError.new(nil, line, column, 0, problem, nil)
        end
        private_class_method :syntax_error

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
