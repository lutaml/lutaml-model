# frozen_string_literal: true

require "nokogiri"

module Lutaml
  module Model
    module Schema
      class SchemaBuilder
        # Nokogiri adapter for XSD schema generation
        # Wraps Nokogiri::XML::Builder to provide schema building capabilities
        class Nokogiri
          attr_reader :builder

          def initialize(options = {}, &block)
            encoding = options[:encoding] || "UTF-8"
            if block_given?
              @builder = ::Nokogiri::XML::Builder.new(encoding: encoding) do |xml|
                yield(xml)
              end
            else
              @builder = ::Nokogiri::XML::Builder.new(encoding: encoding)
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
              builder.to_xml(indent: indent)
            else
              builder.to_xml
            end
          end
        end
      end
    end
  end
end