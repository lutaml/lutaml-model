# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      # Compiles RELAX NG Compact Syntax (RNC) into Lutaml::Model Ruby source.
      #
      # RNC support is a thin adapter: the rng gem parses the compact syntax
      # into Rng::Grammar — resolving includes, bracket annotations, and
      # non-leading `start` definitions natively — then RngCompiler performs all
      # model generation and output handling.
      module RncCompiler
        extend self

        autoload :SourceResolver, "#{__dir__}/rnc_compiler/source_resolver"

        DEFAULT_OUTPUT_DIR_PREFIX = "rnc_models"

        def to_models(rnc, options = {})
          require_rnc_parser!

          grammar = parse_grammar(rnc, options)

          RngCompiler.to_models(
            grammar,
            options.merge(default_output_dir: default_output_dir),
          )
        end

        def parse_grammar(rnc, options)
          return rnc if rnc.is_a?(::Rng::Grammar)

          source = SourceResolver.resolve(rnc, options)
          ::Rng.parse_rnc(source.text, location: source.path || source.base_dir)
        end

        def require_rnc_parser!
          return if rnc_parser_available?

          raise "RNC schema compilation requires an rng gem whose " \
                "`Rng.parse_rnc` accepts a `location:` option (for native " \
                "include resolution). Point your Gemfile at an rng version " \
                "that provides it."
        end

        # rng gained the `location:` option (native include resolution) after
        # the 0.3.7 release; the released parse_rnc takes only `(rnc)`.
        def rnc_parser_available?
          defined?(::Rng::Grammar) && ::Rng.respond_to?(:parse_rnc) &&
            ::Rng.method(:parse_rnc).parameters.any? { |_type, name| name == :location }
        end

        def default_output_dir
          "#{DEFAULT_OUTPUT_DIR_PREFIX}_#{Time.now.to_i}"
        end

        private :parse_grammar, :require_rnc_parser!, :rnc_parser_available?,
                :default_output_dir
      end
    end
  end
end
