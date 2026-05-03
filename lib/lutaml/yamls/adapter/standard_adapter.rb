# frozen_string_literal: true

require "yaml"

module Lutaml
  module Yamls
    module Adapter
      class StandardAdapter < Document
        FORMAT_SYMBOL = :yamls

        def self.parse(yamls, _options = {})
          parse_with_stream(yamls)
        end

        def self.parse_with_stream(yamls)
          results = []

          YAML.load_stream(yamls) do |doc|
            next if doc.nil?

            results << doc
          end

          results
        rescue Psych::SyntaxError => e
          warn "Skipping invalid yaml: #{e.message}"
          parse_with_split(yamls)
        end

        def self.parse_with_split(yamls)
          results = []

          yamls.split(/^---\s*$/).each do |yaml|
            next if yaml.strip.empty?

            begin
              doc = YAML.safe_load(yaml, aliases: true)
              results << doc unless doc.nil?
            rescue Psych::SyntaxError => e
              warn "Skipping invalid yaml: #{e.message}"
            end
          end

          results
        end
        private_class_method :parse_with_stream, :parse_with_split

        def to_yamls(*_args)
          (@yamls || []).map do |yaml|
            YAML.dump(yaml).strip
          end.join("\n")
        end
      end
    end
  end
end
