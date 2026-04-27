# frozen_string_literal: true

require "moxml"

module Lutaml
  module Xml
    module Schema
      class Builder
        # Moxml-based adapter for XSD schema generation (Oga backend)
        # Uses Moxml::Builder's method_missing DSL for element creation.
        class Oga
          def initialize(options = {}, &block)
            @encoding = options[:encoding] || "UTF-8"
            @builder = Moxml::Builder.new(Moxml.new)

            block&.call(@builder)
          end

          # Generate the XSD schema XML string
          def to_xml(_options = {})
            xml = @builder.document.root.to_xml(declaration: false, expand_empty: false)
            "<?xml version=\"1.0\" encoding=\"#{@encoding}\"?>\n#{xml}"
          end

          # Forward all other methods to the builder
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
