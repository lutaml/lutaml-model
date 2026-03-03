# frozen_string_literal: true

module Lutaml::Xml::Schema::Xsd::Errors
      # Builder for constructing detailed error messages
      #
      # @example Building an error message
      #   builder = MessageBuilder.new(error)
      #   message = builder.build
      class MessageBuilder
        # @return [EnhancedError] The error to build message for
        attr_reader :error

        # Initialize message builder
        #
        # @param error [EnhancedError] The error to build message for
        def initialize(error)
          @error = error
        end

        # Build complete error message
        #
        # @return [String] Formatted error message
        def build
          parts = []
          parts << header
          parts << context_details if @error.context && !@error.context.to_h.empty?
          parts << suggestions_section if @error.respond_to?(:suggestions) && @error.suggestions.any?
          parts << troubleshooting_section if @error.respond_to?(:troubleshooting_tips) && @error.troubleshooting_tips.any?
          parts.compact.join("\n\n")
        end

        private

        # Build error header
        #
        # @return [String] Error header
        def header
          severity = @error.respond_to?(:severity) ? @error.severity.to_s.upcase : "ERROR"
          "#{severity}: #{@error.message}"
        end

        # Build context details section
        #
        # @return [String, nil] Context details
        def context_details
          return nil unless @error.context

          details = @error.context.to_h
          return nil if details.empty?

          lines = ["Context:"]
          details.each do |key, value|
            lines << "  #{format_key(key)}: #{value}"
          end
          lines.join("\n")
        end

        # Build suggestions section
        #
        # @return [String, nil] Suggestions
        def suggestions_section
          suggestions = @error.suggestions
          return nil if suggestions.empty?

          lines = ["Did you mean?"]
          suggestions.take(5).each do |suggestion|
            similarity_info = suggestion.similarity < 1.0 ? " (#{suggestion.similarity_percentage}% match)" : ""
            lines << "  • #{suggestion.text}#{similarity_info}"
          end
          lines.join("\n")
        end

        # Build troubleshooting section
        #
        # @return [String, nil] Troubleshooting tips
        def troubleshooting_section
          tips = @error.troubleshooting_tips
          return nil if tips.empty?

          lines = ["Troubleshooting tips:"]
          tips.each_with_index do |tip, i|
            lines << "  #{i + 1}. #{tip}"
          end
          lines.join("\n")
        end

        # Format context key for display
        #
        # @param key [Symbol, String] Context key
        # @return [String] Formatted key
        def format_key(key)
          key.to_s.split("_").map(&:capitalize).join(" ")
        end
      end
end
