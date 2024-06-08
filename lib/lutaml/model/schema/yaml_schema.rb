# lib/lutaml/model/schema/yaml_schema.rb
require "yaml"

module Lutaml
  module Model
    module Schema
      class YamlSchema
        def self.generate(klass, options = {})
          schema = {
            "type" => "map",
            "mapping" => generate_mapping(klass),
          }
          YAML.dump(schema)
        end

        private

        def self.generate_mapping(klass)
          klass.attributes.each_with_object({}) do |(name, attr), mapping|
            mapping[name] = { "type" => get_yaml_type(attr.type) }
          end
        end

        def self.get_yaml_type(type)
          case type
          when Lutaml::Model::Type::String
            "str"
          when Lutaml::Model::Type::Integer
            "int"
          when Lutaml::Model::Type::Boolean
            "bool"
          when Lutaml::Model::Type::Float
            "float"
          when Lutaml::Model::Type::Array
            "seq"
          when Lutaml::Model::Type::Hash
            "map"
          else
            "str" # Default to string for unknown types
          end
        end
      end
    end
  end
end
