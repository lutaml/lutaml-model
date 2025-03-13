require "toml-rb"
require_relative "document"

module Lutaml
  module Model
    module Toml
      class TomlRbAdapter < Document
        def self.parse(toml, _options = {})
          TomlRB.parse(toml)
        end

        def to_toml(*)
          TomlRB.dump(to_h)
        end
      end
    end
  end
end
