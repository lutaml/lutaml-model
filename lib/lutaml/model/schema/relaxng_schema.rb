require "nokogiri"

module Lutaml
  module Model
    module Schema
      class RelaxngSchema
        extend SharedMethods

        def self.generate(klass, options = {})
          register = lookup_register(options[:register])
          builder = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
            xml.grammar(xmlns: "http://relaxng.org/ns/structure/1.0") do
              generate_start(xml, klass)
              generate_define(xml, klass, register)
            end
          end

          options[:pretty] ? builder.to_xml(indent: 2) : builder.to_xml
        end

        def self.generate_start(xml, klass)
          xml.start do
            xml.ref(name: klass.name)
          end
        end

        def self.generate_attributes(xml, klass, register)
          klass.attributes.each do |name, attr|
            attr_type = attr.type(register)
            if attr_type <= Lutaml::Model::Serialize
              xml.ref(name: attr_type.name)
            elsif attr.collection?
              xml.zeroOrMore do
                xml.element(name: name) do
                  xml.data(type: get_relaxng_type(attr_type))
                end
              end
            else
              xml.element(name: name) do
                xml.data(type: get_relaxng_type(attr_type))
              end
            end
          end
        end

        def self.generate_define(xml, klass, register)
          xml.define(name: klass.name) do
            xml.element(name: klass.name) do
              generate_attributes(xml, klass, register)
            end
          end

          klass.attributes.each_value do |attr|
            if attr.type(register) <= Lutaml::Model::Serialize
              generate_define(xml, attr.type(register), register)
            end
          end
        end

        def self.get_relaxng_type(type)
          {
            Lutaml::Model::Type::String => "string",
            Lutaml::Model::Type::Integer => "integer",
            Lutaml::Model::Type::Boolean => "boolean",
            Lutaml::Model::Type::Float => "float",
            Lutaml::Model::Type::Decimal => "decimal",
            Lutaml::Model::Type::Hash => "string",
          }[type] || "string" # Default to string for unknown types
        end
      end
    end
  end
end
