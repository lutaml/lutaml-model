require "oga"
require_relative "xml_document"
require_relative "oga/document"
require_relative "oga/element"
require_relative "builder/oga"

module Lutaml
  module Model
    module XmlAdapter
      class OgaAdapter < XmlDocument
        def self.parse(xml, options = {})
          options[:encoding] ||= xml.encoding || "UTF-8"
          xml.encode("UTF-16").encode!("UTF-8")
          parsed = ::Oga.parse_xml(xml)
          @root = Oga::Element.new(parsed.children.first)
          new(@root, options[:encoding])
        end

        def to_xml(options = {})
          builder = Builder::Oga.build(options) do |builder|
            build_element(builder, @root, options)
          end
          builder.document.children.last.children << ::Oga::XML::Text.new(text: "\n")
          xml_data = builder.to_xml.encode!(options[:parse_encoding])
          options[:declaration] ? declaration(options) + xml_data : xml_data
        end
      end
    end
  end
end
