# frozen_string_literal: true

require 'parsanol'

module Lutaml
  module Lml
    # Parse pipeline only: preprocess → parse → transform → process →
    # build. View resolution and label enrichment are a separate,
    # explicit post-parse step (ViewResolution) — file I/O for imports
    # does not belong inside parsing.
    class Pipeline
      def self.call(input)
        new(input).call
      end

      def initialize(input)
        @input = Source.wrap(input)
      end

      def call
        data = Preprocessor.call(@input)
        hash = parse_raw(data)
        hash = DataProcessor.process(hash)
        build_document(hash)
      end

      private

      def parse_raw(data)
        Transform.new.apply(Parser.new.parse(data))
      rescue Parsanol::ParseFailed => e
        raise ParsingError.new(failure_message(e), diagnostic: parse_diagnostic(e))
      end

      def parse_diagnostic(error)
        line, column = failure_location(error)
        Diagnostic.build(
          'parse/LML-001',
          message: error.message.lines.first.to_s.strip,
          file: @input.path,
          line: line,
          column: column,
        )
      end

      # Parsanol releases up to 1.3.57 annotate native failures with a
      # byte offset marker but report cause.position as 0; fixed parsanol
      # already carries the correct location in the message. Only
      # rebuild the location when the marker is present.
      def failure_message(error)
        detail = error.message.lines.first.to_s.strip
        line, column = failure_location(error)
        location = (" at line #{line} char #{column}." if line && !detail.match?(/at line \d+ char \d+/))
        "#{detail}#{location}\ncause: #{error.parse_failure_cause&.ascii_tree}"
      end

      def failure_location(error)
        cause = error.parse_failure_cause
        offset = error.message[/@@parsanol_pos:(\d+)/, 1]&.to_i
        return cause.source.line_and_column(offset) if offset && cause&.source

        match = error.message.match(/at line (\d+) char (\d+)/)
        match ? [match[1].to_i, match[2].to_i] : [nil, nil]
      end

      def build_document(hash)
        document = DocumentBuilder.new(DocumentBuilder::DEFAULT_REGISTRY).build(:document, hash)
        document.source_path = @input.path
        document
      end
    end
  end
end
