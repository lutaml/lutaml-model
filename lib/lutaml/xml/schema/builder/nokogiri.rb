# frozen_string_literal: true

# TODO: Replace with Moxml::Builder once all callers are migrated from
# Nokogiri::XML::Builder's method_missing DSL (e.g., xml.schema, xml.element)
# to Moxml's explicit element() API.
require "nokogiri"

module Lutaml
  module Xml
    module Schema
      class Builder
        # Nokogiri adapter for XSD schema generation
        # Wraps Nokogiri::XML::Builder to provide schema building capabilities
        class Nokogiri
          attr_reader :builder

          def initialize(options = {}, &block)
            encoding = options[:encoding] || "UTF-8"
            @builder = if block
                         ::Nokogiri::XML::Builder.new(encoding: encoding,
&block)
                       else
                         ::Nokogiri::XML::Builder.new(encoding: encoding)
                       end
          end

          # Generate the XSD schema XML string
          # @param options [Hash] formatting options
          # @option options [Boolean] :pretty Pretty print with indentation
          # @option options [Integer] :indent Number of spaces for indentation (default: 2)
          # @return [String] XSD XML string
          def to_xml(options = {})
            if options[:pretty]
              indent = options[:indent] || 2
              @builder.to_xml(indent: indent)
            else
              @builder.to_xml
            end
          end
        end
      end
    end
  end
end
