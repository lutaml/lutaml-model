# frozen_string_literal: true

require 'parsanol'

module Lutaml
  module Lml
    # Converts the raw parsanol tree into the processed hash, retaining
    # source positions as non-serialized metadata.
    class Transform < Parsanol::Transform
      VISIBILITY_MAP = {
        '-' => 'private',
        '#' => 'protected',
        '~' => 'package',
      }.freeze

      rule(visibility_modifier: simple(:visibility_value)) do
        VISIBILITY_MAP.fetch(visibility_value.to_s, 'public')
      end
      # An empty `until` capture is an empty sequence, not an empty
      # string: `""` parses the dq_string body as [] (parsanol
      # repetition semantics). A present, zero-length string value is
      # distinct from an absent one (RS 3001 §String values); only the
      # :string capture is normalized, other empty sequences stay [].
      rule(string: sequence(:empty_string)) { { string: '' } }

      # RS 3001 §String values: the only two escapes are backslash-quote
      # and backslash-backslash (the grammar rejects every other
      # backslash), so unescaping is removing the backslash before
      # those two characters.
      rule(string: simple(:escaped)) { { string: Lutaml::Lml::Transform.unescape(escaped.to_s) } }

      # Rule blocks evaluate in a Parsanol::Context, so this helper is
      # a class method the block reaches through the class.
      # @param body [String] raw string body as captured between quotes
      # @return [String] the value with \" and \\ resolved
      def self.unescape(body)
        body.gsub(/\\(["'\\])/) { Regexp.last_match(1) }
      end

      # Global scalar normalizer: every leaf becomes a string (or stays
      # nil). No stripping — name and type tokens are interior-bounded
      # in the grammar (class_run/type_run/quoted_name_run), so quoted
      # string values keep their padding verbatim (RS 3001 §String
      # values).
      rule(simple(:value)) { value.nil? ? value : value.to_s }

      # Block captures (definition bodies, block comments) read their
      # surrounding layout as content — a block's first line break and
      # closing indentation are layout, not prose. parsanol only fires
      # hash-keyed rules at selected tree positions, so the strip is a
      # post-pass walk, not a rule.
      BLOCK_KEYS = %i[definition comments].freeze

      def apply(tree, context = nil)
        processed = super
        attach_positions(tree, processed)
        strip_block_layout(processed)
      end

      # Retains the source position of name/key captures as a :position
      # hash beside the transformed value. The document builder moves it
      # onto the model as non-serialized metadata (see Positioned).
      def attach_positions(raw, processed)
        case raw
        when Hash
          return unless processed.is_a?(Hash)

          slice = capture_slice(raw[:name]) || capture_slice(raw[:key]) ||
                  capture_slice(raw[:value_name]) || capture_slice(raw[:lml_version])
          processed[:position] = position_hash(slice) if slice

          raw.each_key do |key|
            attach_positions(raw[key], processed[key]) if processed.key?(key)
          end
        when Array
          return unless processed.is_a?(Array)

          raw.each_with_index do |item, index|
            attach_positions(item, processed[index]) if index < processed.length
          end
        end
      end

      # A name capture is either a bare token (a Slice) or a quoted
      # string (a hash holding the inner Slice).
      def capture_slice(node)
        return node if node.is_a?(Parsanol::Slice)
        return node[:string] if node.is_a?(Hash) && node[:string].is_a?(Parsanol::Slice)

        nil
      end

      def position_hash(slice)
        line, column = slice.line_and_column
        {
          line: line,
          column: column,
          offset: slice.offset,
          length: slice.content.to_s.bytesize,
        }
      end

      def strip_block_layout(node)
        case node
        when Hash
          node.each_with_object({}) do |(key, value), result|
            result[key] = if BLOCK_KEYS.include?(key) && value.is_a?(String)
                            value.strip
                          else
                            strip_block_layout(value)
                          end
          end
        when Array then node.map { |item| strip_block_layout(item) }
        else node
        end
      end
    end
  end
end
