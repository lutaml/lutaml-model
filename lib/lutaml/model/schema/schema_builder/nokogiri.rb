# frozen_string_literal: true

require "moxml"

module Lutaml
  module Model
    module Schema
      class SchemaBuilder
        # Moxml-based adapter for XSD schema generation (Nokogiri backend)
        # Uses Moxml::Builder's method_missing DSL for element creation.
        class Nokogiri
          attr_reader :builder

          def initialize(options = {}, &block)
            @encoding = options[:encoding] || "UTF-8"
            @builder = Moxml::Builder.new(Moxml.new)

            block&.call(@builder)
          end

          # Generate the XSD schema XML string
          def to_xml(options = {})
            indent = options[:pretty] ? (options[:indent] || 2) : 0
            decl = "<?xml version=\"1.0\" encoding=\"#{@encoding}\"?>\n"
            "#{decl}#{@builder.document.root.to_xml(declaration: false, indent: indent, expand_empty: false)}\n"
          end
        end
      end
    end
  end
end
