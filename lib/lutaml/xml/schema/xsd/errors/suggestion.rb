# frozen_string_literal: true

module Lutaml::Xml::Schema::Xsd::Errors
      # Value object representing a suggestion for error resolution
      #
      # @example Creating a suggestion
      #   suggestion = Suggestion.new(
      #     text: "gml:CodeType",
      #     similarity: 0.85,
      #     explanation: "Did you mean 'gml:CodeType'?"
      #   )
      class Suggestion
        # @return [String] The suggestion text
        attr_reader :text

        # @return [Float] Similarity score (0.0 to 1.0)
        attr_reader :similarity

        # @return [String] Explanation of the suggestion
        attr_reader :explanation

        # Initialize a suggestion
        #
        # @param text [String] The suggestion text
        # @param similarity [Float] Similarity score (0.0 to 1.0)
        # @param explanation [String, nil] Optional explanation
        def initialize(text:, similarity: 1.0, explanation: nil)
          @text = text
          @similarity = similarity.to_f
          @explanation = explanation || "Did you mean '#{text}'?"
        end

        # Get similarity percentage
        #
        # @return [Integer] Similarity as percentage (0-100)
        def similarity_percentage
          (@similarity * 100).round
        end

        # Convert to hash
        #
        # @return [Hash] Suggestion as hash
        def to_h
          {
            text: @text,
            similarity: @similarity,
            explanation: @explanation,
          }
        end

        # Compare suggestions by similarity (higher is better)
        #
        # @param other [Suggestion] Another suggestion
        # @return [Integer] Comparison result
        def <=>(other)
          other.similarity <=> @similarity
        end
      end
end
