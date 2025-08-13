require "tomlib"
require_relative "document"

module Lutaml
  module Model
    module Toml
      class TomlibAdapter < Document
        # Issue warning for problematic platforms
        if RUBY_PLATFORM.include?("mingw") && RUBY_VERSION < "3.3"
          require_relative "../services/logger"
          Logger.warn(
            "The Tomlib adapter may cause segmentation faults on Windows " \
            "with Ruby < 3.3 when parsing invalid TOML. Consider using the " \
            "TomlRB adapter instead.",
            __FILE__
          )
        end

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
