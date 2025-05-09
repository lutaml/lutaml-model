require_relative "base_schema"
require "yaml"

module Lutaml
  module Model
    module Schema
      class YamlSchema < BaseSchema
        class << self
          def generate(
            klass,
            id: nil,
            title: nil,
            description: nil,
            pretty: false
          )
            options = {
              schema: "http://json-schema.org/draft-04/schema",
              id: id,
              title: title,
              description: description,
              pretty: pretty,
            }

            super(klass, options)
          end

          def format_schema(schema, options)
            <<~SCHEMA
              %YAML 1.1
              #{options[:pretty] ? schema.to_yaml : YAML.dump(schema)}
            SCHEMA
          end
        end

        def self.lookup_register(register)
          return register.id if register.is_a?(Lutaml::Model::Register)

          register.nil? ? :default : register
        end
      end
    end
  end
end
