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

        # TODO: Is this really needed?
        def self.to_yaml(attributes, *args)
          new(attributes).to_yaml(*args)
        end

        # TODO: Is this really needed?
        def self.from_yaml(yaml, klass)
          data = parse(yaml)
          mapped_attrs = klass.send(:apply_mappings, data, :yaml)
          klass.new(mapped_attrs)
        end
      end
    end
  end
end
