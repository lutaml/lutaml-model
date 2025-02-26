require_relative "base_schema"
require "json"

module Lutaml
  module Model
    module Schema
      class JsonSchema < BaseSchema
        class << self
          def generate(
            klass,
            id: nil,
            title: nil,
            description: nil,
            pretty: false
          )
            options = {
              schema: "https://json-schema.org/draft/2020-12/schema",
              id: id,
              title: title,
              description: description,
              pretty: pretty,
            }

            super(klass, options)
          end

          def format_schema(schema, options)
            options[:pretty] ? JSON.pretty_generate(schema) : schema.to_json
          end
        end

        def self.lookup_register(register)
          return register.id if register.is_a?(Lutaml::Model::Register)

          register.nil? ? Lutaml::Model::Config.default_register : register
        end
      end
    end
  end
end
