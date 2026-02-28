# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      # SchemaBuilder provides an adapter-agnostic interface for XSD schema generation
      # It wraps XML builders (Nokogiri, Oga) to generate XSD documents
      #
      # NOTE: Schema generation is separate from XML parsing. While the XML parsing
      # adapters (Nokogiri, Oga, Ox, REXML) handle reading/writing XML documents,
      # schema generation requires an XML builder API which is only implemented for
      # Nokogiri and Oga. When the configured XML adapter is Ox or REXML, we use
      # Nokogiri for schema generation since it has the most complete builder API.
      class SchemaBuilder
        autoload :Nokogiri, "#{__dir__}/schema_builder/nokogiri"
        autoload :Oga, "#{__dir__}/schema_builder/oga"

        attr_reader :builder, :adapter_type

        # Supported schema builders (separate from XML parsing adapters)
        SUPPORTED_BUILDERS = %i[nokogiri oga].freeze

        def initialize(adapter_type: nil, options: {}, &block)
          # Use specified adapter, or configured XML adapter, or default to Nokogiri
          requested_adapter = adapter_type || Config.xml_adapter_type || :nokogiri

          # Schema generation requires a builder API which only Nokogiri and Oga provide
          # Ox and REXML are valid XML parsing adapters but don't have schema builder implementations
          @adapter_type = if SUPPORTED_BUILDERS.include?(requested_adapter)
                            requested_adapter
                          else
                            :nokogiri
                          end
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
          end
        end
      end
    end
  end
end
