# lib/lutaml/model/toml_adapter.rb

module Lutaml
  module Model
    module TomlAdapter
      class TomlObject
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

      class Document < TomlObject
        def self.parse(toml)
          raise NotImplementedError, "Subclasses must implement `parse`."
        end

        def to_toml(*args)
          raise NotImplementedError, "Subclasses must implement `to_toml`."
        end
      end
    end
  end
end
