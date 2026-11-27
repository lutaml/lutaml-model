# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      # SchemaBuilder provides an adapter-agnostic interface for XSD schema generation
      # It wraps XML builders (Nokogiri, Oga) to generate XSD documents
      #
      # NOTE: Schema generation is separate from XML parsing. While the XML parsing
      # adapters (Nokogiri, Oga, Ox, REXML) handle reading/writing XML documents,
      # schema generation requires an XML builder API which is only implemented for
      # Nokogiri and Oga. When the configured XML adapter is Ox or REXML, we use
      # Nokogiri for schema generation since it has the most complete builder API.
      class Builder
        autoload :Nokogiri, "#{__dir__}/builder/nokogiri"
        autoload :Oga, "#{__dir__}/builder/oga"
        autoload :Moxml, "#{__dir__}/builder/moxml"

        attr_reader :builder, :adapter_type

        # Supported schema builders (separate from XML parsing adapters)
        SUPPORTED_BUILDERS = %i[nokogiri oga].freeze

        def initialize(adapter_type: nil, options: {}, &block)
          # Use specified adapter, or configured XML adapter, or default to Nokogiri
          requested_adapter = adapter_type || Lutaml::Xml.moxml_engine

          # Engines with a dedicated wrapper keep it (byte-identical
          # emission); every other configured engine generates through
          # the moxml layer (#1184) — the wrapper follows the engine
          # instead of silently substituting Nokogiri.
          @adapter_type = requested_adapter
          @options = options
          @builder = create_builder(&block)
        end

        # Generate the XSD schema XML string
        # @param options [Hash] formatting options
        # @option options [Boolean] :pretty Pretty print with indentation
        # @return [String] XSD XML string
        def to_xml(options = {})
          @builder.to_xml(options)
        end

        private

        def create_builder(&block)
          case @adapter_type
          when :nokogiri
            Nokogiri.new(@options, &block)
          when :oga
            Oga.new(@options, &block)
          else
            Moxml.new(@options, &block)
          end
        end
      end
    end
  end
end
