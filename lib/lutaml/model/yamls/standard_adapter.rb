require "yaml"
require_relative "document"

module Lutaml
  module Model
    module Yamls
      class StandardAdapter < Document
        FORMAT_SYMBOL = :yamls

        def self.parse(yamls, _options = {})
          results = []

          yamls.split(/^---\n/).each do |yaml|
            next if yaml.strip.empty?

            begin
              results << YAML.safe_load(yaml, aliases: true)
            rescue Psych::SyntaxError => e
              warn "Skipping invalid yaml: #{e.message}"
            end
          end

          results
        end

        def to_yamls(*_args)
          (@yamls || []).map do |yaml|
            YAML.dump(yaml).strip
          end.join("\n")
        end
      end
    end
  end
end
