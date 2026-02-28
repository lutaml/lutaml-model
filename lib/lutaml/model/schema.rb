# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      autoload :BaseSchema, "#{__dir__}/schema/base_schema"
      autoload :SharedMethods, "#{__dir__}/schema/shared_methods"
      autoload :Helpers, "#{__dir__}/schema/helpers"
      autoload :JsonSchema, "#{__dir__}/schema/json_schema"
      autoload :XsdSchema, "#{__dir__}/schema/xsd_schema"
      autoload :RelaxngSchema, "#{__dir__}/schema/relaxng_schema"
      autoload :YamlSchema, "#{__dir__}/schema/yaml_schema"
      autoload :XmlCompiler, "#{__dir__}/schema/xml_compiler"
      autoload :Generator, "#{__dir__}/schema/generator"
      autoload :Renderer, "#{__dir__}/schema/renderer"
      autoload :Decorators, "#{__dir__}/schema/decorators"
      autoload :SchemaBuilder, "#{__dir__}/schema/schema_builder"
      autoload :XsBuiltinTypes, "#{__dir__}/schema/xs_builtin_types"

      def self.to_json(klass, options = {})
        JsonSchema.generate(klass, options)
      end

      def self.to_xsd(klass, options = {})
        XsdSchema.generate(klass, options)
      end

      def self.to_relaxng(klass, options = {})
        RelaxngSchema.generate(klass, options)
      end

      def self.to_yaml(klass, options = {})
        YamlSchema.generate(klass, options)
      end

      def self.from_xml(xml, options = {})
        XmlCompiler.to_models(xml, options)
      end
    end
  end
end
