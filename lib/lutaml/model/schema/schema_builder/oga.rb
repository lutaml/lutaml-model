# frozen_string_literal: true

require "moxml"

module Lutaml
  module Model
    module Schema
      class SchemaBuilder
        # Moxml-based adapter for XSD schema generation (Oga backend)
        # Uses moxml's document/element API with a method_missing DSL
        # that mirrors Nokogiri::XML::Builder's interface.
        class Oga
          attr_reader :builder, :document

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
          # @return [String] XSD XML string
          def to_xml(_options = {})
            xml = @document.root.to_xml(declaration: false, expand_empty: false)
            "<?xml version=\"1.0\" encoding=\"#{@encoding}\"?>\n#{xml}"
          end

          # Forward all other methods to the builder wrapper
          def method_missing(method_name, ...)
            @builder.public_send(method_name, ...)
          end

          def respond_to_missing?(method_name, include_private = false)
            @builder.respond_to?(method_name, include_private) || super
          end
        end
      end
    end
  end
end
