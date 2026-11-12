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

        # True where the yeptris engine loads (libyeptris present for
        # this platform) AND answers a probe parse. A require alone
        # does not prove the engine: a half-initialized Yeptris
        # constant (the poison-process state the gem documents)
        # passes const_defined? and require while every parse fails,
        # and the native parse error then surfaces on valid input.
        # Any failure — missing native, engine error, or a binding and
        # native binary out of sync (NameError on a missing FFI surface,
        # yeptris 0.6.34.2 x64-mingw-ucrt) — reports false instead of
        # raising, so optional-engine callers (detection) gate on it and
        # fall back to the standard lane.
        def self.available?
          require_engine
          native_ready?
        rescue LoadError
          false
        end

        def self.native_ready?
          return @native_ready unless @native_ready.nil?

          @native_ready = begin
            # rubocop:disable-next Naming/VariableNumber -- upstream schema literal
            ::Yeptris::YAML.load("native_probe: 1", schema: :compat_11)
            true
          rescue StandardError
            false
          end
        end
        private_class_method :native_ready?

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

        # Dump rides the native Yeptris::Psych face when the engine's
        # emitter is byte-parity with the standard adapter, else the
        # inherited standard (Psych) dump. The contract: a stored
        # fixture generated under one adapter must round-trip
        # byte-exactly under the other, or a host whose bundle flips
        # the default engine rewrites every stored YAML (the 0.8.171
        # default-flip broke relaton's SAE suite exactly this way).
        # Parity is capability-based, not version-based: the probe
        # dumps the shape battery through the native face and the
        # standard adapter and compares byte-for-byte. Plain-scalar
        # folding landed in yeptris 0.6.62.1, bare null-valued keys
        # after literal blocks in 0.6.63 (#1264); any engine that
        # misses a shape keeps the standard dump without a version
        # floor.
        def to_yaml(_options = {})
          return super unless self.class.native_dump_parity?

          require "yeptris/psych"
          Yeptris::Psych.dump(@attributes)
        end

        # True when the native emitter produces byte-identical output
        # to the standard adapter across the shape battery (the same
        # shapes the adapter spec pins: plain-scalar folding, null
        # keys after literal blocks and quoted siblings, flow, unicode,
        # nesting, multiline). Memoized; any failure — missing psych,
        # engine error, non-parity bytes — reports false so dump rides
        # the standard adapter.
        def self.native_dump_parity?
          return @native_dump_parity unless @native_dump_parity.nil?

          @native_dump_parity = begin
            require "yeptris/psych"
            dump_parity_shapes.all? do |shape|
              native = Yeptris::Psych.dump(shape)
              # The comparison target is the literal parent class, not
              # this class's to_yaml: the override routes back here
              # while the probe is still unmemoized, recursing to a
              # SystemStackError.
              native == Lutaml::Yaml::Adapter::StandardAdapter.new(shape).to_yaml
            end
          rescue StandardError
            false
          end
        end

        # The document shapes whose byte treatment historically differs
        # between emitters (leptris/yeptris#863, #1264). Keep in sync
        # with the adapter spec's battery.
        def self.dump_parity_shapes
          [
            {
              "title" => "Taxonomy and Definitions for Terms Related to " \
                         "Driving Automation Systems for On-Road Motor " \
                         "Vehicles for On-Road Motor Vehicles",
              "roles" => %w[admin dev],
            },
            { "s" => "line1\nline2", "n" => nil },
            { "q" => "has: colon", "n" => nil },
            { "u" => "héllo wörld", "num" => "007", "f" => 1.5, "e" => "" },
            { "deep" => { "deeper" => [{ "x" => "y" }, [4, 5]] } },
            { "multi" => "para one\n\npara two", "dash" => "a - b - c",
              "omitted" => nil },
            { "a" => 1, "b" => [1, 2, 3], "c" => { "d" => true } },
          ]
        end
      end
    end
  end
end
