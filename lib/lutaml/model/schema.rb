require_relative "schema/shared_methods"
require_relative "schema/json_schema"
require_relative "schema/xsd_schema"
require_relative "schema/relaxng_schema"
require_relative "schema/yaml_schema"
require_relative "schema/xml_compiler"
require_relative "schema/lml_compiler"

module Lutaml
  module Model
    module Schema
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

      def self.from_lml(lml, options = {})
        LmlCompiler.to_models(lml, options)
      end
    end
  end
end
