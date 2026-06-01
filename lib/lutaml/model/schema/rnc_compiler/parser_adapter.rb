# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module RncCompiler
        # Resolves RNC input, applies local compatibility preprocessing, and
        # returns the rng gem's parsed grammar model.
        class ParserAdapter
          attr_reader :warnings

          def initialize(input, options)
            @input = input
            @options = options
            @warnings = []
          end

          def parse
            return input if input.is_a?(::Rng::Grammar)

            source = SourceResolver.new(input, options).resolve
            result = preprocess(source)
            warnings.concat(result.warnings)

            ::Rng.parse_rnc(result.source)
          end

          private

          attr_reader :input, :options

          def preprocess(source)
            visited = []
            visited << source.path if source.path

            Preprocessor.new.call(
              source.text,
              base_dir: source.base_dir,
              visited: visited,
            )
          end
        end
      end
    end
  end
end
