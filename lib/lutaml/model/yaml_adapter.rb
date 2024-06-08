# lib/lutaml/model/yaml_adapter.rb
require "yaml"

module Lutaml
  module Model
    module YamlAdapter
      module Standard
        def self.to_yaml(model, *args)
          YAML.dump(model.hash_representation, *args)
        end

        def self.from_yaml(yaml, klass)
          data = YAML.safe_load(yaml, permitted_classes: [Date, Time, DateTime, Symbol])
          klass.new(data)
        end
      end
    end
  end
end
