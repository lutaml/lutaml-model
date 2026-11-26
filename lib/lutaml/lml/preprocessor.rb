# frozen_string_literal: true

module Lutaml
  module Lml
    # Expands `include` directives before parsing. Unterminated block
    # comments are rejected here; line comments are grammar trivia.
    class Preprocessor
      attr_reader :input_file

      def initialize(input_file)
        @input_file = Source.wrap(input_file)
      end

      class << self
        def call(input_file)
          new(input_file).call
        end
      end

      def call
        expand_lines(@input_file.read, @input_file.base_dir, [], @input_file.path)
      end

      private

      # Comments (`//`, `/* */`) are consumed by the grammar's trivia
      # skip (parsanol-ruby#134); only include directives are expanded
      # here. Line structure is preserved so parse-error positions
      # match the source.
      def expand_lines(text, base_dir, chain, file_path)
        validate_block_comments(text, file_path)
        text.split(/\r?\n/)
            .each_with_index
            .flat_map { |line, index| expand_line(line, base_dir, chain, file_path, index + 1) }
            .join("\n")
      end

      def expand_line(line, base_dir, chain, file_path, line_number)
        path = include_path(line, base_dir)
        return [line] unless path

        if chain.include?(path)
          raise Error.new(
            "circular include detected: #{path}",
            diagnostic: Diagnostic.build(
              'parse/LML-003',
              message: "circular include detected: #{path}",
              file: file_path, line: line_number, column: 1
            ),
          )
        end

        expand_lines(read_included(path, file_path, line_number),
                     File.dirname(path), chain + [path], path)
      end

      def include_path(line, base_dir)
        # Linear-time match: `\S.*` cannot overlap the leading `[ \t]+`,
        # so a line of spaces after `include` fails in O(n) rather than
        # backtracking quadratically (CodeQL ReDoS).
        match = line.match(/\A[ \t]*include[ \t]+(\S.*)\z/)
        return nil unless match

        File.expand_path(trim_trailing_comment(match[1].strip), base_dir)
      end

      def trim_trailing_comment(path)
        path.sub(%r{\s+(//|/\*).*}, '')
      end

      def read_included(path, file_path, line_number)
        File.read(path, encoding: 'UTF-8')
      rescue SystemCallError => e
        raise Error.new(
          "cannot read include #{path}: #{e.message}",
          diagnostic: Diagnostic.build(
            'parse/LML-003',
            message: "cannot read include: #{path}",
            file: file_path, line: line_number, column: 1
          ),
        )
      end

      # Quote-aware scan: a `/*` opened outside a string literal or a
      # line comment must close before end of input. The grammar's
      # trivia would otherwise reject the text with an unrelated
      # expected-token error.
      def validate_block_comments(text, file_path)
        quote = nil
        pos = 0
        open_index = nil
        while pos < text.length
          ch = text[pos]
          if quote
            if ch == '\\'
              pos += 2
              next
            end
            quote = nil if ch == quote
          elsif open_index
            if text[pos, 2] == '*/'
              open_index = nil
              pos += 1
            end
          elsif ['"', "'"].include?(ch)
            quote = ch
          elsif text[pos, 2] == '//'
            pos = text.index("\n", pos) || text.length
            next
          elsif text[pos, 2] == '/*'
            open_index = pos
          end
          pos += 1
        end
        return unless open_index

        line = text[0...open_index].count("\n") + 1
        column = open_index - (text.rindex("\n", open_index) || -1)
        raise Error.new(
          "unterminated block comment at line #{line}",
          diagnostic: Diagnostic.build(
            'parse/LML-002',
            message: 'unterminated block comment',
            file: file_path, line: line, column: column
          ),
        )
      end
    end
  end
end
