require "json"
require_relative "document"

module Lutaml
  module Model
    module Jsonl
      class StandardAdapter < Document
        FORMAT_SYMBOL = :jsonl

        def self.parse(jsonl, _options = {})
          results = []
          jsonl.split("\n").each do |line|
            next if line.strip.empty?

            begin
              results << JSON.parse(line, create_additions: false)
            rescue JSON::ParserError => e
              warn "Skipping invalid line: #{e.message}"
            end
          end

          results
        end

        def to_jsonl(*_args)
          (@jsons || []).map do |json|
            JSON.generate(json)
          end.join("\n")
        end
      end
    end
  end
end
