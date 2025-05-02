require "yaml"

module Lutaml
  module Model
    module Schema
      class YamlSchema
        def self.generate(klass, options = {})
          register = lookup_register(options[:register])
          schema = generate_schema(klass, register)
          options[:pretty] ? schema.to_yaml : YAML.dump(schema)
        end

        def self.generate_schema(klass, register)
          {
            "type" => "map",
            "mapping" => generate_mapping(klass, register),
          }
        end

        def self.generate_mapping(klass, register)
          klass.attributes.each_with_object({}) do |(name, attr), mapping|
            mapping[name.to_s] = generate_attribute_schema(attr, register)
          end
        end

        def self.generate_attribute_schema(attr, register)
          attr_type = attr.type(register)
          if attr_type <= Lutaml::Model::Serialize
            generate_schema(attr_type, register)
          elsif attr.collection?
            {
              "type" => "seq",
              "sequence" => [{ "type" => get_yaml_type(attr_type) }],
            }
          else
            { "type" => get_yaml_type(attr_type) }
          end
        end

        def self.get_yaml_type(type)
          {
            Lutaml::Model::Type::String => "str",
            Lutaml::Model::Type::Integer => "int",
            Lutaml::Model::Type::Boolean => "bool",
            Lutaml::Model::Type::Float => "float",
            Lutaml::Model::Type::Decimal => "float",
            Lutaml::Model::Type::Hash => "map",
          }[type] || "str" # Default to string for unknown types
        end

        def self.lookup_register(register)
          return register if register.is_a?(Lutaml::Model::Register)

          if register.nil?
            Lutaml::Model::Config.default_register
          else
            Lutaml::Model::GlobalRegister.lookup(register)
          end
        end
      end
    end
  end
end
