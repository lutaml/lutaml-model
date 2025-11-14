# frozen_string_literal: true

module Lutaml
  module Model
    module Schema
      # SchemaBuilder provides an adapter-agnostic interface for XSD schema generation
      # It wraps XML builders (Nokogiri, Oga) to generate XSD documents
      class SchemaBuilder
        attr_reader :builder, :adapter_type

        def initialize(adapter_type: nil, options: {}, &block)
          @adapter_type = adapter_type || Config.xml_adapter_type || :nokogiri
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
            require_relative "schema_builder/nokogiri"
            SchemaBuilder::Nokogiri.new(@options, &block)
          when :oga
            require_relative "schema_builder/oga"
            SchemaBuilder::Oga.new(@options, &block)
          else
            raise UnknownAdapterTypeError, "Unknown adapter type: #{@adapter_type}. Supported: [:nokogiri, :oga]"
          end
        end
      end
    end
  end
end