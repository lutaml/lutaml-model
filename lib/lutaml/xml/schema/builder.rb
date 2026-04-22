# frozen_string_literal: true

module Lutaml
  module Xml
    module Schema
      # SchemaBuilder provides an adapter-agnostic interface for XSD schema generation
      # Uses moxml for all XML construction, with adapter-specific backends for
      # Nokogiri and Oga. When the configured XML adapter is Ox or REXML, we
      # default to Nokogiri for schema generation.
      class Builder
        autoload :Nokogiri, "#{__dir__}/builder/nokogiri"
        autoload :Oga, "#{__dir__}/builder/oga"

        # Shared moxml-based builder that provides a method_missing DSL
        # for schema generation. Used by both Nokogiri and Oga adapters.
        # Supports: xml.element_name(attrs) { nested_block }
        # TODO: Remove once Moxml::Builder supports method_missing DSL
        #   https://github.com/lutaml/moxml/issues/65
        class MoxmlSchemaBuilder
          def initialize(document, context)
            @document = document
            @context = context
            @current_element = nil
          end

          def method_missing(method_name, *args)
            attributes = args.first.is_a?(Hash) ? args.first : {}
            text_content = args.first.is_a?(String) ? args.first : nil

            element = @document.create_element(method_name.to_s)

            attributes.each do |name, value|
              element[name.to_s] = value.to_s
            end

            if @current_element
              @current_element.add_child(element)
            else
              @document.root = element
            end

            if text_content
              text_node = @document.create_text(text_content)
              element.add_child(text_node)
            end

            if block_given?
              parent = @current_element
              @current_element = element
              yield
              @current_element = parent
            end

            element
          end

          def respond_to_missing?(_method_name, _include_private = false)
            true
          end
        end

        attr_reader :builder, :adapter_type

        # Supported schema builders (separate from XML parsing adapters)
        SUPPORTED_BUILDERS = %i[nokogiri oga].freeze

        def initialize(adapter_type: nil, options: {}, &)
          # Use specified adapter, or configured XML adapter, or default to Nokogiri
          requested_adapter = adapter_type || Lutaml::Model::Config.xml_adapter_type || :nokogiri

          # Schema generation requires a builder API which only Nokogiri and Oga provide
          # Ox and REXML are valid XML parsing adapters but don't have schema builder implementations
          @adapter_type = if SUPPORTED_BUILDERS.include?(requested_adapter)
                            requested_adapter
                          else
                            :nokogiri
                          end
          @options = options
          @builder = create_builder(&)
        end

        # Generate the XSD schema XML string
        # @param options [Hash] formatting options
        # @option options [Boolean] :pretty Pretty print with indentation
        # @return [String] XSD XML string
        def to_xml(options = {})
          @builder.to_xml(options)
        end

        private

        def create_builder(&)
          case @adapter_type
          when :nokogiri
            Nokogiri.new(@options, &)
          when :oga
            Oga.new(@options, &)
          end
        end
      end
    end
  end
end
