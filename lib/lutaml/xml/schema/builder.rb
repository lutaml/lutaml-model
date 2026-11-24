# frozen_string_literal: true

require "moxml"

module Lutaml
  module Xml
    module Schema
      # SchemaBuilder generates XSD documents through the moxml builder,
      # engine-agnostic: the serialization engine is moxml's runtime
      # choice (leptris whenever present) and the builder DSL is the
      # same on every engine.
      #
      # Schema generation is separate from XML parsing: parse adapters
      # and the schema builder both ride the moxml layer, so one
      # builder serves every configured parse adapter (nokogiri, ox,
      # oga, rexml, leptris) with no per-engine dispatch.
      class Builder
        # Engines the schema builder accepts. Any moxml-supported engine
        # works; the per-engine Nokogiri/Oga wrapper classes remain
        # available under Schema::Builder::{Nokogiri,Oga}.
        SUPPORTED_BUILDERS = %i[nokogiri oga ox rexml leptris].freeze

        attr_reader :builder, :adapter_type

        def initialize(adapter_type: nil, options: {}, &block)
          @context = Moxml.new(adapter_type)
          @context.config.default_encoding = options[:encoding] || "UTF-8"
          @adapter_type = adapter_type
          @options = options
          @builder = Moxml::Builder.new(@context)

          # Builder-as-block-arg contract: the generator block receives the
          # builder and drives the tag DSL through it.
          block&.call(@builder)
          @builder.build { }
        end

        # Generate the XSD schema XML string
        #
        # Emission parity with the pre-moxml face: the declaration with
        # the configured encoding, two-space indentation and self-closed
        # empty elements.
        #
        # @param options [Hash] formatting options
        # @option options [Boolean] :pretty Pretty print with indentation
        # @option options [Integer] :indent Number of spaces (default: 2)
        # @return [String] XSD XML string
        def to_xml(options = {})
          @builder.document.to_xml(
            declaration: true,
            indent: options[:indent] || 2,
            expand_empty: false,
          )
        end
      end
    end
  end
end
