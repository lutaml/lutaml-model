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
          TEXT_CHOICE_WARNING =
            "RNC attribute text/value choices are normalized to text; " \
            "literal alternatives are not enforced."
          INCLUDE_PATTERN =
            /^[ \t]*include\s+(?<quote>["'])(?<href>[^"']+)\k<quote>(?<tail>[^\n]*)(?:\n|$)/
          NCNAME = /\\?[A-Za-z_][A-Za-z0-9_.-]*/
          QNAME = /#{NCNAME}(?::#{NCNAME})?/
          QNAME_AT_POS = /\G#{QNAME}/
          ATTRIBUTE_PATTERN =
            /(attribute\s+#{QNAME}\s*\{\s*)([^{}]*)\s*\}/m
          OCCURRENCE_MARKERS = %w[* + ?].freeze

          def call(source, base_dir: nil, visited: [])
            warnings = []
            stripped = strip_rnc_annotations(source.to_s, warnings)
            normalized = normalize_ref_occurrences(
              normalize_attribute_text_choices(stripped, warnings),
            )
            expanded = expand_includes(normalized, base_dir, visited, warnings)

            Result.new(source: expanded, warnings: warnings)
          end

          private

          def expand_includes(source, base_dir, visited, warnings)
            return source unless base_dir

            source.gsub(INCLUDE_PATTERN) do
              href = Regexp.last_match(:href)
              tail = Regexp.last_match(:tail).to_s
              raise_unsupported_include_override(href) if tail.include?("{")

              include_path = File.expand_path(href, base_dir)
              result = preprocess_include(include_path, visited)
              append_warnings(warnings, result.warnings)
              "#{result.source}\n"
            end
          end

          def preprocess_include(path, visited)
            raise "Circular RNC include detected: #{path}" if visited.include?(path)
            raise "RNC include file not found: #{path}" unless File.file?(path)

            visited << path
            begin
              call(File.read(path), base_dir: File.dirname(path), visited: visited)
            ensure
              visited.delete(path)
            end
          end

          def raise_unsupported_include_override(href)
            raise "RNC include override blocks are not supported: #{href}"
          end

          # Iterates the source, transparently skipping past strings and
          # comments, and yielding to the block on every other character to
          # let it append to `out` and return the next index. Shared scanner
          # skeleton for the bracket-annotation and occurrence-marker passes.
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

          # The current rng RNC parser preserves cardinality for `(ref)*` but
          # drops it for the compact shorthand `ref*`. RFC XML v3 uses the
          # shorthand heavily, so normalize repeated bare tokens into the grouped
          # spelling before parsing.
          def normalize_ref_occurrences(source)
            scan(source) do |out, src, i|
              if identifier_start?(src[i])
                stop = read_identifier(src, i)
                token = src[i...stop]

                if OCCURRENCE_MARKERS.include?(src[stop])
                  out << "(#{token})#{src[stop]}"
                  stop + 1
                else
                  out << token
                  stop
                end
              else
                out << src[i]
                i + 1
              end
            end
          end

          # The rng parser's attribute grammar accepts `text` and value choices
          # separately, but not mixed forms like `attribute indent { text |
          # "adaptive" }`. For model generation this is a string attribute, so
          # normalize that compact form to plain `text` and report the tradeoff.
          def normalize_attribute_text_choices(source, warnings)
            source.gsub(ATTRIBUTE_PATTERN) do
              prefix = Regexp.last_match(1)
              content = Regexp.last_match(2)

              if content.match?(/(\A|\|)\s*text\s*(\||\z)/)
                append_warning(warnings, TEXT_CHOICE_WARNING)
                "#{prefix}text }"
              else
                "#{prefix}#{content} }"
              end
            end
          end

          def identifier_start?(char)
            char == "\\" || char&.match?(/[A-Za-z_]/)
          end

          def read_identifier(source, index)
            m = QNAME_AT_POS.match(source, index)
            m ? m.end(0) : index
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

          def append_warnings(warnings, more_warnings)
            more_warnings.each { |warning| append_warning(warnings, warning) }
          end
        end
      end
    end
  end
end
