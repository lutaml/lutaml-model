require "multi_json"
require_relative "document"

module Lutaml
  module Model
    module Json
      class MultiJsonAdapter < Document
        def self.parse(json, _options = {})
          data = MultiJson.load(json)
          new(data)
        end

        def to_json(*args)
          MultiJson.dump(to_h, *args)
        end
      end
    end
  end
end
