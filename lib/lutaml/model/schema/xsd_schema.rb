# lib/lutaml/model/schema/xsd_schema.rb
require "nokogiri"

module Lutaml
  module Model
    module Schema
      class XsdSchema
        def self.generate(klass, options = {})
          schema = Nokogiri::XML::Builder.new do |xml|
            xml.schema(xmlns: "http://www.w3.org/2001/XMLSchema") do
              xml.element(name: klass.name) do
                xml.complexType do
                  xml.sequence do
                    generate_elements(klass, xml)
                  end
                end
              end
            end
          end
          schema.to_xml
        end

        private

        def self.generate_elements(klass, xml)
          klass.attributes.each do |name, attr|
            xml.element(name: name, type: get_xsd_type(attr.type))
          end
        end

        def self.get_xsd_type(type)
          case type
          when Lutaml::Model::Type::String
            "xs:string"
          when Lutaml::Model::Type::Integer
            "xs:integer"
          when Lutaml::Model::Type::Boolean
            "xs:boolean"
          when Lutaml::Model::Type::Float
            "xs:float"
          when Lutaml::Model::Type::Decimal
            "xs:decimal"
          when Lutaml::Model::Type::Array
            "xs:array"
          when Lutaml::Model::Type::Hash
            "xs:object"
          else
            "xs:string" # Default to string for unknown types
          end
        end
      end
    end
  end
end
