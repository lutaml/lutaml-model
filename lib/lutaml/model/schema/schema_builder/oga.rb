# frozen_string_literal: true

require "oga"

module Lutaml
  module Model
    module Schema
      class SchemaBuilder
        # Oga adapter for XSD schema generation
        # Wraps Oga XML building to provide schema building capabilities
        class Oga
          attr_reader :builder, :document

          def initialize(options = {})
            @encoding = options[:encoding] || "UTF-8"
            @document = ::Oga::XML::Document.new
            @builder = OgaBuilderWrapper.new(@document, @encoding)

            # Execute the block if provided
            yield(@builder) if block_given?
          end

          # Generate the XSD schema XML string
          # @param options [Hash] formatting options
          # @option options [Boolean] :pretty Pretty print with indentation (note: Oga doesn't support pretty printing directly)
          # @return [String] XSD XML string
          def to_xml(_options = {})
            xml = @document.to_xml
            # Add XML declaration with encoding
            "<?xml version=\"1.0\" encoding=\"#{@encoding}\"?>\n#{xml}"
          end

          # Forward all other methods to the builder wrapper
          def method_missing(method_name, ...)
            @builder.public_send(method_name, ...)
          end

          def respond_to_missing?(method_name, include_private = false)
            @builder.respond_to?(method_name, include_private) || super
          end

          # Wrapper that provides a Nokogiri-like API for Oga
          class OgaBuilderWrapper
            def initialize(document, encoding)
              @document = document
              @encoding = encoding
              @current_element = nil
            end

            # Create a method that acts like Nokogiri's builder DSL
            # e.g., xml.schema { } or xml.element { }
            def method_missing(method_name, *args)
              attributes = args.first || {}

              # Create the element
              element = ::Oga::XML::Element.new(name: method_name.to_s)

              # Add attributes
              attributes.each do |name, value|
                element.attributes << ::Oga::XML::Attribute.new(
                  name: name.to_s,
                  value: value.to_s,
                )
              end

              # Add to document or current element
              if @current_element
                @current_element.children << element
              else
                @document.children << element
              end

              # If block given, process nested elements
              if block_given?
                parent = @current_element
                @current_element = element
                yield
                @current_element = parent
              end

              element
            end

            def respond_to_missing?(_method_name, _include_private = false)
              true # Accept any method for element creation
            end
          end
        end
      end
    end
  end
end
