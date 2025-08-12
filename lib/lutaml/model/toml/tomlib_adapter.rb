require "tomlib"
require_relative "document"

module Lutaml
  module Model
    module Toml
      class TomlibAdapter < Document
        def self.parse(toml, _options = {})
          Tomlib.load(toml)
        rescue StandardError => e
          raise Tomlib::ParseError, e.message
        rescue Exception => e # rubocop:disable Lint/RescueException
          raise Tomlib::ParseError, "Native error during parse: #{e.message}"
        end

        def to_toml(*)
          Tomlib.dump(to_h)
          # Tomlib::Generator.new(to_h).toml_str
        end
      end
    end
  end
end
