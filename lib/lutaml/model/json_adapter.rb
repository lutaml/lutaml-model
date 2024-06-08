# lib/lutaml/model/json_adapter.rb
require "json"

module Lutaml
  module Model
    module JsonAdapter
      class JsonObject
        attr_reader :attributes

        def initialize(attributes = {})
          @attributes = attributes
        end

        def [](key)
          @attributes[key]
        end

        def []=(key, value)
          @attributes[key] = value
        end

        def to_h
          @attributes
        end
      end

      class Document < JsonObject
        def self.parse(json)
          raise NotImplementedError, "Subclasses must implement `parse`."
        end

        def to_json(*args)
          raise NotImplementedError, "Subclasses must implement `to_json`."
        end
      end
    end
  end
end
