# frozen_string_literal: true

module Lutaml
  module Model
    module Consolidation
      class PatternChunker
        # @param collection [Collection] the collection instance
        # @param map [ConsolidationMap] consolidation configuration
        # @param tokens [Array] mixed content tokens from parent
        def process(collection, map, tokens)
          rules = map.rules
          element_rules = rules.grep(PatternElementRule)
          trigger_rule = element_rules.first
          content_rule = rules.find { |r| r.is_a?(PatternContentRule) }

          entries = []
          current = nil

          tokens.each do |token|
            case token_type(token)
            when :element
              rule = element_rules.find do |r|
                r.element_name == token_name(token)
              end
              next unless rule

              if rule == trigger_rule && current
                entries << current
                current = nil
              end

              current ||= map.group_class.new
              current.public_send(:"#{rule.target}=", token_text(token))
            when :text
              next unless content_rule && current

              text = token_text(token)
              next if text.strip.empty?

              current.public_send(:"#{content_rule.target}=", text)
            end
          end

          entries << current if current
          collection.public_send(:"#{map.to}=", entries)
        end

        private

        # Token interface — adapted to parent's mixed content representation.
        # Subclasses or runtime adapters override these for format-specific tokens.

        # @param token [Object] a mixed content token
        # @return [Symbol] :element or :text
        def token_type(token)
          if token.respond_to?(:node_type)
            token.node_type == :element ? :element : :text
          elsif token.is_a?(Hash)
            token[:type] || (token.key?(:text) ? :text : :element)
          else
            :text
          end
        end

        # @param token [Object] a mixed content token
        # @return [String, nil] the element name
        def token_name(token)
          if token.respond_to?(:name)
            token.name
          elsif token.is_a?(Hash)
            token[:name]
          end
        end

        # @param token [Object] a mixed content token
        # @return [String, nil] the text content
        def token_text(token)
          if token.respond_to?(:text)
            token.text
          elsif token.is_a?(Hash)
            token[:text]
          end
        end
      end
    end
  end
end
