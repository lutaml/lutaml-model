# lib/lutaml/model/json_adapter/standard.rb
require "json"
require_relative "../json_adapter"

module Lutaml
  module Model
    module JsonAdapter
      class StandardDocument < Document
        def self.parse(json)
          attributes = JSON.parse(json, create_additions: false)
          new(attributes)
        end

        def to_json(*args)
          JSON.generate(@attributes, *args)
        end
      end
    end
  end
end
