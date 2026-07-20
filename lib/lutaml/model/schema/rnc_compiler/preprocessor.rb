# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      module RncCompiler
        # Local compatibility layer for RNC syntax the current rng parser does
        # not yet accept while preserving the compiler boundary at Rng::Grammar.
        class Preprocessor
          Result = Struct.new(:source, :warnings, keyword_init: true)

          ANNOTATION_WARNING =
            "RNC annotations are ignored by compatibility preprocessing."

          def call(source)
            warnings = []
            stripped = strip_rnc_annotations(source.to_s, warnings)

            Result.new(source: stripped, warnings: warnings)
          end

          private

          # Iterates the source, transparently skipping past strings and
          # comments, and yielding to the block on every other character to
          # let it append to `out` and return the next index. Scanner skeleton
          # for the bracket-annotation stripping pass.
          def scan(source)
            out = +""
            i = 0

            while i < source.length
              if string_start?(source, i)
                stop = string_end(source, i)
                out << source[i...stop]
                i = stop
              elsif source[i] == "#"
                stop = source.index("\n", i) || source.length
                out << source[i...stop]
                i = stop
              else
                i = yield(out, source, i)
              end
            end

            out
          end

          # The current rng parser exposes annotation grammar, but it does not
          # accept the RFC XML v3 pattern form `[ a:defaultValue = "..." ]
          # attribute ...` in content. Strip bracket annotations as a narrow
          # compatibility pass and leave full RNC parsing to the rng gem.
          def strip_rnc_annotations(source, warnings)
            scan(source) do |out, src, i|
              if src[i] == "["
                stop = skip_annotation(src, i)
                if stop == i
                  out << src[i]
                  next i + 1
                end

                append_warning(warnings, ANNOTATION_WARNING)
                out << " "
                stop
              else
                out << src[i]
                i + 1
              end
            end
          end

          def string_start?(source, index)
            ['"', "'"].include?(source[index])
          end

          def string_end(source, index)
            quote = source[index]
            triple = source[index, 3] == quote * 3
            stop = index + (triple ? 3 : 1)

            loop do
              if triple
                found = source.index(quote * 3, stop)
                return source.length unless found

                return found + 3
              end

              return source.length if stop >= source.length

              if source[stop] == "\\"
                stop += 2
              elsif source[stop] == quote
                return stop + 1
              else
                stop += 1
              end
            end
          end

          def skip_annotation(source, index)
            depth = 0
            i = index

            while i < source.length
              if string_start?(source, i)
                i = string_end(source, i)
                next
              end

              case source[i]
              when "["
                depth += 1
              when "]"
                depth -= 1
                return i + 1 if depth.zero?
              end

              i += 1
            end

            index
          end

          def append_warning(warnings, warning)
            warnings << warning unless warnings.include?(warning)
          end
        end
      end
    end
  end
end
