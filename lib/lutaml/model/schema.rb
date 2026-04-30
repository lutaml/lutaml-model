# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      autoload :BaseSchema, "#{__dir__}/schema/base_schema"
      autoload :SharedMethods, "#{__dir__}/schema/shared_methods"
      autoload :Helpers, "#{__dir__}/schema/helpers"
      autoload :JsonSchema, "#{__dir__}/schema/json_schema"
      autoload :YamlSchema, "#{__dir__}/schema/yaml_schema"
      Lutaml::Model::RuntimeCompatibility.autoload_native(
        self,
        {
          XmlCompiler: "#{__dir__}/schema/xml_compiler",
        },
      )
      autoload :Generator, "#{__dir__}/schema/generator"
      autoload :Renderer, "#{__dir__}/schema/renderer"
      autoload :Decorators, "#{__dir__}/schema/decorators"

      # Registry for format-specific schema methods.
      # Format plugins register their schema methods at load time.
      @registered_methods = {}

      # Register a schema method dynamically.
      # Format plugins call this to add their schema generation/parsing methods.
      #
      # @param name [Symbol] The method name (e.g., :to_xsd, :from_xml)
      # @param block [Proc] The implementation
      def self.register_method(name, &block)
        @registered_methods[name] = block
        define_singleton_method(name, &block)
      end

      # Check if a schema method is registered.
      #
      # @param name [Symbol] The method name
      # @return [Boolean]
      def self.method_registered?(name)
        @registered_methods.key?(name)
      end

      def self.to_json(klass, options = {})
        JsonSchema.generate(klass, options)
      end

      def self.to_yaml(klass, options = {})
        YamlSchema.generate(klass, options)
      end

      # XML-specific methods (to_xsd, to_relaxng, from_xml) are registered
      # by Lutaml::Xml at load time via register_method.
      # If called without XML loaded, raise a helpful error.
      def self.to_xsd(_klass, _options = {})
        raise "XSD schema generation requires lutaml-xml. Add it to your Gemfile."
      end

      def self.to_relaxng(_klass, _options = {})
        raise "RELAX NG schema generation requires lutaml-xml. Add it to your Gemfile."
      end

      def self.from_xml(_xml, _options = {})
        raise "XML schema compilation requires lutaml-xml. Add it to your Gemfile."
      end
    end
  end
end
