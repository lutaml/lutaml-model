# lib/lutaml/model/json_adapter/multi_json.rb
require "multi_json"
require_relative "../json_adapter"

module Lutaml
  module Model
    module JsonAdapter
      class MultiJsonDocument < Document
        def self.parse(json)
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
