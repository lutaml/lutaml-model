module Lutaml
  module Model
    class UnknownAdapterTypeError < Error
      # Available adapters by format
      AVAILABLE_ADAPTERS = {
        xml: %w[nokogiri ox oga rexml],
        json: %w[standard multi_json oj],
        yaml: %w[standard],
        toml: %w[tomlib toml_rb],
        hash: %w[standard],
        jsonl: %w[standard],
        yamls: %w[standard],
      }.freeze

      def initialize(adapter_name, type_name)
        @adapter_name = adapter_name.to_s
        @type_name = extract_type_name(type_name)

        super()
      end

      def to_s
        msg = "Unknown adapter type: `#{@type_name}` for `#{@adapter_name}` format."
        msg += " #{suggestion}" if suggestion
        msg
      end

      private

      def extract_type_name(type_name)
        type_name.to_s.gsub("_adapter", "")
      end

      def available_types
        AVAILABLE_ADAPTERS[@adapter_name.to_sym] || []
      end

      def suggestion
        return nil if available_types.empty?

        closest = find_closest_match(@type_name, available_types)
        if closest
          "Did you mean: `#{closest}`? "
        end
        "Available adapters for `#{@adapter_name}`: #{available_types.map do |t|
          "`#{t}`"
        end.join(', ')}."
      end

      # Simple Levenshtein-based suggestion finder
      def find_closest_match(input, candidates)
        return nil if input.nil? || input.empty?

        candidates.min_by do |candidate|
          levenshtein_distance(input.downcase, candidate.downcase)
        end.tap do |closest|
          # Only return if distance is reasonable (not a random match)
          return nil if closest && levenshtein_distance(input.downcase,
                                                        closest.downcase) > ([
                                                          input.length, closest.length
                                                        ].max / 2) + 2
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
              matrix[i - 1][j] + 1,      # deletion
              matrix[i][j - 1] + 1,      # insertion
              matrix[i - 1][j - 1] + cost, # substitution
            ].min
          end
        end

        matrix[a.length][b.length]
      end
    end
  end
end
