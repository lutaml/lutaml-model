# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      # Compiles RELAX NG Compact Syntax (RNC) into Lutaml::Model Ruby source.
      #
      # RNC support is intentionally a thin adapter: the rng gem parses the
      # compact syntax into Rng::Grammar, then RngCompiler performs all model
      # generation and output handling. The Preprocessor only papers over RNC
      # syntax the current rng parser does not yet accept.
      module RncCompiler
        extend self

        autoload :Preprocessor,   "#{__dir__}/rnc_compiler/preprocessor"
        autoload :SourceResolver, "#{__dir__}/rnc_compiler/source_resolver"

        DEFAULT_OUTPUT_DIR_PREFIX = "rnc_models"

        def to_models(rnc, options = {})
          require_rnc_parser!

          grammar = parse_grammar(rnc, options)
          drop_synthetic_start_define!(grammar)

          RngCompiler.to_models(
            grammar,
            options.merge(default_output_dir: default_output_dir),
          )
        end

        def parse_grammar(rnc, options)
          return rnc if rnc.is_a?(::Rng::Grammar)

          source = SourceResolver.resolve(rnc, options)
          visited = source.path ? [source.path] : []
          result = Preprocessor.new.call(
            source.text,
            base_dir: source.base_dir,
            visited: visited,
          )
          append_warnings(options, result.warnings)

          ::Rng.parse_rnc(result.source)
        end

        # When RNC source uses `start = X` or `start |= X`, the rng gem
        # lowers it to a <define name="start"> instead of a <start>. Drop
        # the synthetic define so RngCompiler does not emit a spurious
        # `Start` class. Reachable defines are still compiled via the
        # sweep over grammar.define in RngCompiler.compile_grammar.
        def drop_synthetic_start_define!(grammar)
          return unless grammar.start.to_a.empty?

          grammar.define.reject! { |define| define.name == "start" }
        end

        def require_rnc_parser!
          return if defined?(::Rng::Grammar) &&
            defined?(::Rng::RncParser) &&
            ::Rng.respond_to?(:parse_rnc)

          raise "RNC schema compilation requires the rng gem. " \
                "Add `gem \"rng\"` to your Gemfile."
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

        private :parse_grammar, :drop_synthetic_start_define!,
                :require_rnc_parser!, :append_warnings, :default_output_dir
      end
    end
  end
end
