# lib/lutaml/model/yaml_adapter.rb
require "yaml"

module Lutaml
  module Model
    module YamlAdapter
      module Standard
        def self.to_yaml(model, *args)
          YAML.dump(model.hash_representation(:yaml), *args)
        end

        def self.from_yaml(yaml, klass)
          data = parse(yaml)
          mapped_attrs = klass.send(:apply_mappings, data, :yaml)
          klass.new(mapped_attrs)
        end

        def self.parse(yaml)
          YAML.safe_load(yaml,
                         permitted_classes: [Date, Time, DateTime, Symbol,
                                             BigDecimal, Hash, Array])
        end
      end
    end
  end
end
