# frozen_string_literal: true

module Lutaml
  module Xml
    # Represents a single namespace declaration extracted from parsed XML.
    #
    # This is the core OOP representation of a parsed namespace declaration.
    # Namespace URIs are treated as opaque strings — the model layer makes
    # no assumptions about their format (http://, urn:, or plain strings).
    #
    # @example
    #   decl = ParsedNamespaceDeclaration.new(
    #     uri: "http://example.com/ns",
    #     prefix: "ex",
    #     format: :prefix,
    #     declared_at_path: []
    #   )
    #
    class ParsedNamespaceDeclaration
      # URI is an opaque string - no format assumptions
      # @return [String]
      attr_reader :uri

      # nil for default namespace, String for prefixed
      # @return [String, nil]
      attr_reader :prefix

      # :default or :prefix
      # @return [Symbol]
      attr_reader :format

      # Array of element path segments where this was declared
      # [] = root, ["child"] = child element, etc.
      # @return [Array<String>]
      attr_reader :declared_at_path

      # Canonical URI — set when this is an alias declaration
      # (the model-level canonical namespace URI)
      # @return [String, nil]
      attr_reader :canonical_uri

      # Original URI from input — set when this is an alias declaration
      # (the actual URI that appeared in the input XML)
      # @return [String, nil]
      attr_reader :original_uri

      def initialize(uri:, prefix: nil, format: :default, declared_at_path: [],
                   canonical_uri: nil, original_uri: nil)
        @uri = uri
        @prefix = prefix
        @format = format
        @declared_at_path = declared_at_path
        @canonical_uri = canonical_uri
        @original_uri = original_uri
        validate!
      end

      def default_namespace?
        @format == :default
      end

      def prefixed_namespace?
        @format == :prefix
      end

      def alias?
        !@canonical_uri.nil?
      end

      # The effective URI for model resolution (canonical for aliases)
      # @return [String]
      def effective_uri
        @canonical_uri || @uri
      end

      # The URI to emit in serialization (original for aliases, canonical otherwise)
      # @return [String]
      def serialization_uri
        @original_uri || @canonical_uri || @uri
      end

      # Unique key for hash/set operations: prefix + effective_uri
      # @return [String]
      def key
        prefix_str = @prefix ? "#{@prefix}:" : ""
        "#{prefix_str}#{effective_uri}"
      end

      # Equality based on all fields
      # @param other [Object]
      # @return [Boolean]
      def ==(other)
        other.is_a?(ParsedNamespaceDeclaration) &&
          other.uri == @uri &&
          other.prefix == @prefix &&
          other.format == @format &&
          other.declared_at_path == @declared_at_path &&
          other.canonical_uri == @canonical_uri &&
          other.original_uri == @original_uri
      end

      alias eql? ==

      # @return [Integer]
      def hash
        [@uri, @prefix, @format, @declared_at_path, @canonical_uri,
         @original_uri].hash
      end

      # @return [String]
      def inspect
        "#<ParsedNamespaceDecl prefix=#{@prefix.inspect} uri=#{@uri.inspect} " \
          "at=#{@declared_at_path.inspect}>"
      end

      private

      def validate!
        raise ArgumentError, "uri is required" if @uri.nil? || @uri.empty?
        unless %i[default prefix].include?(@format)
          raise ArgumentError, "format must be :default or :prefix"
        end
        unless @declared_at_path.is_a?(Array)
          raise ArgumentError, "declared_at_path must be an Array"
        end
      end
    end
  end
end
