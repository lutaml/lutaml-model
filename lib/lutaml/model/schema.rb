# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      autoload :BaseSchema, "#{__dir__}/schema/base_schema"
      autoload :SharedMethods, "#{__dir__}/schema/shared_methods"
      autoload :Helpers, "#{__dir__}/schema/helpers"
      autoload :JsonSchema, "#{__dir__}/schema/json_schema"
      autoload :YamlSchema, "#{__dir__}/schema/yaml_schema"
      autoload :XmlCompiler, "#{__dir__}/schema/xml_compiler"
      autoload :Generator, "#{__dir__}/schema/generator"
      autoload :Renderer, "#{__dir__}/schema/renderer"
      autoload :Decorators, "#{__dir__}/schema/decorators"

      # XML Schema classes are now in Lutaml::Xml::Schema
      # Use Lutaml::Xml::Schema::XsdSchema, Lutaml::Xml::Schema::RelaxngSchema, etc.

      def self.to_json(klass, options = {})
        JsonSchema.generate(klass, options)
      end

      def self.to_xsd(klass, options = {})
        require_relative "../xml/schema/xsd_schema"
        Lutaml::Xml::Schema::XsdSchema.generate(klass, options)
      rescue LoadError
        raise "XSD schema generation requires lutaml-xml. Add it to your Gemfile."
      end

      def self.to_relaxng(klass, options = {})
        require_relative "../xml/schema/relaxng_schema"
        Lutaml::Xml::Schema::RelaxngSchema.generate(klass, options)
      rescue LoadError
        raise "RELAX NG schema generation requires lutaml-xml. Add it to your Gemfile."
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
