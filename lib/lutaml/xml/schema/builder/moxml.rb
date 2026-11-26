# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      class Builder
        # The moxml-backed schema builder (issue #1184): schema
        # generation rides the CONFIGURED engine through the moxml
        # layer, so every engine with a builder face generates
        # schemas — not only the engines with a dedicated wrapper.
        # The backend resolves from Config's plain symbol; the
        # AdapterResolver's FIXED_ADAPTER_TYPE sentinel never reaches
        # Moxml (the closed #1183 leak).
        #
        # The block receives the Moxml::Builder and drives it with
        # the same method_missing tag DSL the Nokogiri/Oga wrappers
        # expose: tag(attrs) { ... } closures, symbol or string
        # attribute keys, xmlns handled as a namespace declaration.
        class Moxml
          attr_reader :builder

          def initialize(options = {}, &block)
            encoding = options[:encoding] || "UTF-8"
            backend = Lutaml::Model::Config.xml_adapter_type || :nokogiri
            @context = ::Moxml.new(backend)
            @builder = ::Moxml::Builder.new(@context)
            # Nokogiri's Builder emits the declaration when an
            # encoding is given; parity here.
            @builder.declaration(version: "1.0", encoding: encoding)
            yield(@builder) if block
          end

          # Generate the schema XML string
          # @param options [Hash] formatting options
          # @option options [Boolean] :pretty Pretty print with indentation
          # @option options [Integer] :indent Number of spaces (default: 2)
          # @return [String] schema XML string
          def to_xml(options = {})
            doc = @builder.document
            if options[:pretty]
              indent = options[:indent] || 2
              doc.to_xml(indent: indent)
            else
              doc.to_xml
            end
          end
        end
      end
    end
  end
end
