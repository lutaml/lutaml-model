# frozen_string_literal: true

module Lutaml
  module Rdf
    class Literal
      include LanguageTagged

      attr_reader :value, :datatype, :language

      def initialize(value, datatype: nil, language: nil)
        @value = value
        @datatype = datatype
        @language = language
      end

      def to_turtle
        escaped = escape_turtle(value.to_s)
        if language
          "#{escaped}@#{language}"
        elsif datatype
          "#{escaped}^^<#{datatype}>"
        else
          escaped
        end
      end

      def to_jsonld_term
        if language
          { "@value" => value, "@language" => language }
        elsif datatype
          { "@value" => value, "@type" => datatype.to_s }
        else
          value
        end
      end

      def ==(other)
        other.is_a?(self.class) &&
          value == other.value &&
          datatype == other.datatype &&
          language == other.language
      end
      alias_method :eql?, :==

      def hash
        [value, datatype, language].hash
      end

      private

      def escape_turtle(str)
        escaped = str.gsub(/[\n\r\t"\\]/,
                           "\\" => "\\\\",
                           '"' => "\\\"",
                           "\n" => "\\n",
                           "\r" => "\\r",
                           "\t" => "\\t")
        "\"#{escaped}\""
      end
    end
  end
end
