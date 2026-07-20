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
          canonicalize_synthetic_start!(grammar)

          RngCompiler.to_models(
            grammar,
            options.merge(default_output_dir: default_output_dir),
          )
        end

        def parse_grammar(rnc, options)
          return rnc if rnc.is_a?(::Rng::Grammar)

          source = SourceResolver.resolve(rnc, options)
          result = Preprocessor.new.call(source.text)
          append_warnings(options, result.warnings)

          ::Rng.parse_rnc(result.source, location: source.path || source.base_dir)
        end

        # rng lowers a non-leading `start = X` / `start |= X` to a
        # <define name="start"> with an empty <start>. Rebuild it as a real
        # <start> carrying the element/ref RngCompiler compiles, then drop the
        # define so RngCompiler does not also emit a spurious `Start` class.
        def canonicalize_synthetic_start!(grammar)
          return unless grammar.start.to_a.empty?

          synthetic = grammar.define.find { |define| define.name == "start" }
          return unless synthetic

          start = ::Rng::Start.new
          start.element = synthetic.element.to_a.first
          start.ref = synthetic.ref.to_a.first
          grammar.start = [start]
          grammar.define.reject! { |define| define.name == "start" }
        end

        def require_rnc_parser!
          return if rnc_parser_available?

          raise "RNC schema compilation requires the rng gem's main branch " \
                "(Rng.parse_rnc must accept a `location:` option). Add " \
                "`gem \"rng\", git: \"https://github.com/lutaml/rng\", branch: \"main\"` " \
                "to your Gemfile."
        end

        # rng gained the `location:` option (native include resolution) after
        # the 0.3.7 release; the released parse_rnc takes only `(rnc)`.
        def rnc_parser_available?
          defined?(::Rng::Grammar) && ::Rng.respond_to?(:parse_rnc) &&
            ::Rng.method(:parse_rnc).parameters.any? { |_type, name| name == :location }
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

        private :parse_grammar, :canonicalize_synthetic_start!,
                :require_rnc_parser!, :rnc_parser_available?,
                :append_warnings, :default_output_dir
      end
    end
  end
end
