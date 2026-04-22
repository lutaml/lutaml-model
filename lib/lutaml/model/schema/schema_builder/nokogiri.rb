# frozen_string_literal: true

require "moxml"

module Lutaml
  module Model
    module Schema
      class SchemaBuilder
        # Moxml-based adapter for XSD schema generation (Nokogiri backend)
        # Uses moxml's document/element API with a method_missing DSL
        # that mirrors Nokogiri::XML::Builder's interface.
        class Nokogiri
          attr_reader :builder

          def initialize(options = {}, &block)
            @encoding = options[:encoding] || "UTF-8"
            @context = Moxml.new
            @document = @context.create_document
            @builder = Lutaml::Xml::Schema::Builder::MoxmlSchemaBuilder.new(
              @document, @context
            )

            block&.call(@builder)
          end

          # Generate the XSD schema XML string
          # @param options [Hash] formatting options
          # @option options [Boolean] :pretty Pretty print with indentation
          # @option options [Integer] :indent Number of spaces for indentation (default: 2)
          # @return [String] XSD XML string
          def to_xml(options = {})
            indent = options[:pretty] ? (options[:indent] || 2) : 0
            decl = "<?xml version=\"1.0\" encoding=\"#{@encoding}\"?>\n"
            "#{decl}#{@document.root.to_xml(declaration: false, indent: indent, expand_empty: false)}\n"
          end
        end
      end
    end
  end
end
