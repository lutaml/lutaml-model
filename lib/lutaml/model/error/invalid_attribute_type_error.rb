module Lutaml
  module Model
    class InvalidAttributeTypeError < Error
      # Built-in types that users commonly reference
      BUILTIN_TYPES = %w[
        string integer int float boolean date time datetime
        symbol text hash array any uri decimal double long
        short byte base64binary hexbinary
      ].freeze

      def initialize(attr_name, type, context = nil)
        @attr_name = attr_name
        @type = type
        @context = context

        super()
      end

      def to_s
        msg = "Invalid type `#{@type.inspect}` for attribute `#{@attr_name}`."
        msg += " #{@context}." if @context
        msg += " #{type_requirement}"
        msg += " #{suggestion}" if suggestion
        msg
      end

      private

      def type_requirement
        "Type must be a Class that inherits from Lutaml::Model::Type::Value " \
          "or Lutaml::Model::Serialize."
      end

      def suggestion
        return nil unless @type.is_a?(Symbol) || @type.is_a?(String)

        type_str = @type.to_s.downcase

        # Check for common typos in built-in types
        closest = find_closest_match(type_str, BUILTIN_TYPES)
        if closest && closest != type_str
          return "Did you mean `:#{closest}`? " \
                 "Use `:#{closest}` for the built-in #{closest} type."
        end

        # Suggest proper syntax if they used a symbol for a class
        if BUILTIN_TYPES.include?(type_str)
          return "For built-in types, use the symbol form `:#{type_str}` " \
                 "or the class `Lutaml::Model::Type::#{type_str.capitalize}`."
        end

        nil
      end

      # Simple Levenshtein-based suggestion finder
      def find_closest_match(input, candidates)
        return nil if input.nil? || input.empty?

        candidates.min_by do |candidate|
          levenshtein_distance(input.downcase, candidate.downcase)
        end.tap do |closest|
          max_dist = ([input.length, closest.length].max / 2) + 1
          return nil if closest && levenshtein_distance(input.downcase,
                                                        closest.downcase) > max_dist
        end
      end

      # Calculate Levenshtein distance between two strings
      def levenshtein_distance(a, b)
        return a.length if b.empty?
        return b.length if a.empty?

        matrix = Array.new(a.length + 1) do |i|
          Array.new(b.length + 1) do |j|
            if i.zero?
              j
            else
              (j.zero? ? i : 0)
            end
          end
        end

        (1..a.length).each do |i|
          (1..b.length).each do |j|
            cost = a[i - 1] == b[j - 1] ? 0 : 1
            matrix[i][j] = [
              matrix[i - 1][j] + 1,
              matrix[i][j - 1] + 1,
              matrix[i - 1][j - 1] + cost,
            ].min
          end
        end

        matrix[a.length][b.length]
      end
    end
  end
end
