# frozen_string_literal: true

module Lutaml
  module Lml
    # A position in the parsed source: 1-based line and column, with the
    # byte offset and captured length when the parser provides them.
    # Attached to model objects as non-serialized metadata so diagnostics
    # can cite it without changing the document model's wire form.
    class SourcePosition
      attr_reader :line, :column, :offset, :length

      def initialize(line:, column:, offset: nil, length: nil)
        @line = line
        @column = column
        @offset = offset
        @length = length
      end
    end
  end
end
