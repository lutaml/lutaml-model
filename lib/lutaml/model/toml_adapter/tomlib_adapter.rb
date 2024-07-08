# lib/lutaml/model/toml_adapter/tomlib_adapter.rb
require "tomlib"
require_relative "../toml_adapter"

module Lutaml
  module Model
    module TomlAdapter
      class TomlibDocument < Document
        def self.parse(toml)
          data = Tomlib.load(toml)
          new(data)
        end

        def to_toml(*args)
          Tomlib.dump(to_h, *args)
          # Tomlib::Generator.new(to_h).toml_str
        end
      end
    end
  end
end
