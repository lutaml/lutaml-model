require "yaml"
require_relative "yaml_document"

module Lutaml
  module Model
    module YamlAdapter
      class StandardYamlAdapter < YamlDocument
        def self.parse(yaml)
          YAML.safe_load(
            yaml,
            permitted_classes: [Date, Time, DateTime, Symbol,
                                BigDecimal, Hash, Array],
          )
        end

        def to_yaml(options = {})
          YAML.dump(@attributes, options)
        end
      end
    end
  end
end
