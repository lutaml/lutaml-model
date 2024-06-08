# lib/lutaml/model/json_adapter/standard.rb
require "json"
require_relative "../json_adapter"

module Lutaml
  module Model
    module JsonAdapter
      class StandardDocument < Document
        def self.parse(json)
          data = JSON.parse(json)
          new(data)
        end

        def to_json(*args)
          JSON.generate(to_h, *args)
        end
      end
    end
  end
end
