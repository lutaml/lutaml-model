# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      # Compiles RELAX NG Compact Syntax (RNC) into Lutaml::Model Ruby source.
      #
      # RNC support is intentionally a thin adapter: the rng gem parses the
      # compact syntax into Rng::Grammar, then RngCompiler performs all model
      # generation and output handling.
      module RncCompiler
        extend self

        autoload :ParserAdapter,        "#{__dir__}/rnc_compiler/parser_adapter"
        autoload :Preprocessor,         "#{__dir__}/rnc_compiler/preprocessor"
        autoload :SourceResolver,       "#{__dir__}/rnc_compiler/source_resolver"
        autoload :SyntheticStartOutput,
                 "#{__dir__}/rnc_compiler/synthetic_start_output"

        DEFAULT_OUTPUT_DIR_PREFIX = "rnc_models"

        def to_models(rnc, options = {})
          require_rnc_parser!

          opts = normalize_options(options)
          adapter = ParserAdapter.new(rnc, opts)
          grammar = adapter.parse
          append_warnings(opts, adapter.warnings)

          output = RngCompiler.compile(grammar, opts)
          SyntheticStartOutput.remove(output, grammar)

          RngCompiler.dispatch(
            output,
            opts.merge(default_output_dir: default_output_dir),
          )
        end

        def require_rnc_parser!
          return if defined?(::Rng::Grammar) &&
            defined?(::Rng::RncParser) &&
            ::Rng.respond_to?(:parse_rnc)

          raise "RNC schema compilation requires the rng gem. " \
                "Add `gem \"rng\"` to your Gemfile."
        end

        def normalize_options(options)
          opts = options.dup
          opts[:indent]      ||= 2
          opts[:register_id] ||= :default
          opts
        end

        def append_warnings(options, warnings)
          collector = options[:warnings]
          return unless collector.respond_to?(:concat)

          collector.concat(warnings)
          collector.uniq! if collector.respond_to?(:uniq!)
        end

        def default_output_dir
          "#{DEFAULT_OUTPUT_DIR_PREFIX}_#{Time.now.to_i}"
        end

        private :require_rnc_parser!, :normalize_options, :append_warnings,
                :default_output_dir
      end
    end
  end
end
