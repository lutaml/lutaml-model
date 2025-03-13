require "tomlib"
require_relative "document"

module Lutaml
  module Model
    module Toml
      class TomlibAdapter < Document
        def self.parse(toml, _options = {})
          Tomlib.load(toml)
        end

        def to_toml(*)
          Tomlib.dump(to_h)
          # Tomlib::Generator.new(to_h).toml_str
        end
      end
    end
  end
end
