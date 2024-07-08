# lib/lutaml/model/schema/yaml_schema.rb
require "yaml"

module Lutaml
  module Model
    module Schema
      class YamlSchema
        def self.generate(klass, _options = {})
          schema = {
            "type" => "map",
            "mapping" => generate_mapping(klass),
          }
          YAML.dump(schema)
        end

        def self.generate_mapping(klass)
          klass.attributes.each_with_object({}) do |(name, attr), mapping|
            mapping[name.to_s] = { "type" => get_yaml_type(attr.type) }
          end
        end

        def self.get_yaml_type(type)
          {
            Lutaml::Model::Type::String => "str",
            Lutaml::Model::Type::Integer => "int",
            Lutaml::Model::Type::Boolean => "bool",
            Lutaml::Model::Type::Float => "float",
            Lutaml::Model::Type::Decimal => "float", # YAML does not have a separate decimal type, so we use float
            Lutaml::Model::Type::Array => "seq",
            Lutaml::Model::Type::Hash => "map",
          }[type] || "str" # Default to string for unknown types
        end
      end
    end
  end
end
