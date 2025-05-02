require "nokogiri"

module Lutaml
  module Model
    module Schema
      class XsdSchema
        def self.generate(klass, options = {})
          register = lookup_register(options[:register])
          builder = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
            xml.schema(xmlns: "http://www.w3.org/2001/XMLSchema") do
              generate_complex_type(xml, klass, nil, register)
            end
          end

          options[:pretty] ? builder.to_xml(indent: 2) : builder.to_xml
        end

        def self.generate_complex_type(xml, klass, element_name = nil, register)
          xml.element(name: element_name || klass.name) do
            xml.complexType do
              xml.sequence do
                generate_elements(xml, klass, register)
              end
            end
          end
        end

        def self.generate_elements(xml, klass, register)
          klass.attributes.each do |name, attr|
            attr_type = attr.type(register)
            if attr_type <= Lutaml::Model::Serialize
              generate_complex_type(xml, attr_type, name, register)
            elsif attr.collection?
              xml.element(name: name, minOccurs: "0", maxOccurs: "unbounded") do
                xml.complexType do
                  xml.sequence do
                    xml.element(name: "item", type: get_xsd_type(attr_type))
                  end
                end
              end
            else
              xml.element(name: name, type: get_xsd_type(attr_type))
            end
          end
        end

        def self.get_xsd_type(type)
          {
            Lutaml::Model::Type::String => "xs:string",
            Lutaml::Model::Type::Integer => "xs:integer",
            Lutaml::Model::Type::Boolean => "xs:boolean",
            Lutaml::Model::Type::Float => "xs:float",
            Lutaml::Model::Type::Decimal => "xs:decimal",
            Lutaml::Model::Type::Hash => "xs:anyType",
          }[type] || "xs:string" # Default to string for unknown types
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
