# frozen_string_literal: true

module Lutaml
  module Lml
    # The single source of truth for scalar quoting on the emit side:
    # bare only for runs of [A-Za-z0-9_] (the grammar's word rule);
    # double quotes with the two RS 3001 escapes otherwise. Values,
    # attribute keys, and the canonical form all emit through here.
    module Quoting
      BARE_WORD = /\A\w+\z/

      module_function

      # @param scalar [String, #to_s]
      # @return [String] the emitted form: parseable back to scalar
      def quote_scalar(scalar)
        str = scalar.to_s
        return str if str.match?(BARE_WORD)

        quote_always(str)
      end

      # Double-quoted form even when the scalar is a bare word. Used
      # where the grammar only accepts quoted strings (definitions,
      # requires, instance data values, wire names).
      #
      # @param scalar [String, #to_s]
      # @return [String] the double-quoted, escaped form
      def quote_always(scalar)
        escaped = scalar.to_s.gsub('\\') { |bs| bs * 2 }.gsub('"') { |q| "\\#{q}" }
        "\"#{escaped}\""
      end

      # Float#to_s may use exponent notation, for which the language has
      # no literal. Expand it to a plain decimal that parses back to the
      # same Float.
      #
      # @param number [Numeric]
      # @return [String] the emitted form
      def number_scalar(number)
        text = number.to_s
        match = text.match(/\A(-?)(\d+)(?:\.(\d+))?[eE]([+-]?\d+)\z/)
        return text unless match

        integer = match[2]
        digits = integer + match[3].to_s
        point = integer.length + match[4].to_i
        plain =
          if point <= 0
            "0.#{'0' * -point}#{digits}"
          elsif point >= digits.length
            "#{digits}#{'0' * (point - digits.length)}.0"
          else
            "#{digits[0...point]}.#{digits[point..]}"
          end
        "#{match[1]}#{plain}"
      end
    end
  end
end
