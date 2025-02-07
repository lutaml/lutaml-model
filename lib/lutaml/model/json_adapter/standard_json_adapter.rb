require "json"
require_relative "json_document"

module Lutaml
  module Model
    module JsonAdapter
      class StandardJsonAdapter < JsonDocument
        def self.parse(json, _options = {})
          JSON.parse(json, create_additions: false)
        end

        def to_json(*args)
          options = args.first || {}
          if options[:pretty]
            JSON.pretty_generate(@attributes, *args)
          else
            JSON.generate(@attributes, *args)
          end
        end
      end
    end
  end
end
