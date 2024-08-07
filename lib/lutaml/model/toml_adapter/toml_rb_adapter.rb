# lib/lutaml/model/toml_adapter/toml_rb_adapter.rb
require "toml-rb"
require_relative "../toml_adapter"

module Lutaml
  module Model
    module TomlAdapter
      class TomlRbDocument < Document
        def self.parse(toml)
          data = TomlRB.parse(toml)
          new(data)
        end

        def to_toml(*)
          TomlRB.dump(to_h)
        end
      end
    end
  end
end
