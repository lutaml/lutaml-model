require "nokogiri"

module Lutaml
  module Model
    module Schema
      class RelaxngSchema
        def self.generate(klass, _options = {})
          schema = Nokogiri::XML::Builder.new do |xml|
            xml.element(name: klass.name) do
              xml.complexType do
                xml.sequence do
                  generate_elements(klass, xml)
                end
              end
            end
          end
          schema.to_xml
        end

        def self.generate_elements(klass, xml)
          klass.attributes.each do |name, attr|
            xml.element(name: name, type: get_relaxng_type(attr.type))
          end
        end

        def self.get_relaxng_type(type)
          {
            Lutaml::Model::Type::String => "string",
            Lutaml::Model::Type::Integer => "integer",
            Lutaml::Model::Type::Boolean => "boolean",
            Lutaml::Model::Type::Float => "float",
            Lutaml::Model::Type::Array => "array",
            Lutaml::Model::Type::Hash => "object",
          }[type] || "string" # Default to string for unknown types
        end
      end
    end
  end
end
