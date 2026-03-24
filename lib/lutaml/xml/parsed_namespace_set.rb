# frozen_string_literal: true

module Lutaml
  module Xml
    # Collection of parsed namespace declarations, providing OOP access and lookups.
    #
    # Supports lookups by prefix, by URI (canonical or alias), and by original URI.
    # Backward-compatible with plain hash storage via {#to_input_namespaces_hash}
    # and {.from_hash}.
    #
    # @example
    #   set = ParsedNamespaceSet.new([
    #     ParsedNamespaceDeclaration.new(uri: "http://ex", prefix: "a"),
    #     ParsedNamespaceDeclaration.new(uri: "http://ex", prefix: "b"),
    #   ])
    #   set.for_uri("http://ex").size  # => 2
    #   set.prefixes                   # => ["a", "b"]
    #
    class ParsedNamespaceSet
      # @param declarations [Array<ParsedNamespaceDeclaration>]
      def initialize(declarations = [])
        @by_prefix = {}        # prefix string => [ParsedNamespaceDeclaration]
        @by_uri = {}           # effective_uri => [ParsedNamespaceDeclaration]
        @by_original_uri = {} # original_uri => ParsedNamespaceDeclaration
        declarations.each { |d| add(d) }
      end

      # Add a declaration to the set
      # @param declaration [ParsedNamespaceDeclaration]
      # @return [self]
      def add(declaration)
        key = declaration.prefix || :default
        @by_prefix[key] ||= []
        @by_prefix[key] << declaration

        @by_uri[declaration.effective_uri] ||= []
        @by_uri[declaration.effective_uri] << declaration

        if declaration.original_uri
          @by_original_uri[declaration.original_uri] = declaration
        end

        self
      end

      # All declarations for a given prefix
      # @param prefix [String, nil]
      # @return [Array<ParsedNamespaceDeclaration>]
      def for_prefix(prefix)
        @by_prefix[prefix || :default] || []
      end

      # All declarations for a given URI (matches canonical or alias)
      # @param uri [String]
      # @return [Array<ParsedNamespaceDeclaration>]
      def for_uri(uri)
        @by_uri[uri] || []
      end

      # Declaration with a specific (prefix, uri) combination
      # @param prefix [String, nil]
      # @param uri [String]
      # @return [ParsedNamespaceDeclaration, nil]
      def find(prefix, uri)
        for_prefix(prefix).find { |d| d.effective_uri == uri }
      end

      # All declarations at root level
      # @return [Array<ParsedNamespaceDeclaration>]
      def root_declarations
        @by_prefix.values.flatten.select { |d| d.declared_at_path.empty? }
      end

      # All unique effective URIs
      # @return [Array<String>]
      def uris
        @by_uri.keys
      end

      # All unique prefixes (excludes :default)
      # @return [Array<String>]
      def prefixes
        @by_prefix.keys.reject { |k| k == :default }
      end

      # Check if a URI has multiple prefix variants (doubly-defined namespace)
      # @param uri [String]
      # @return [Boolean]
      def multiple_prefixes_for_uri?(uri)
        for_uri(uri).reject(&:default_namespace?).size > 1
      end

      # Serialize to Hash for backward compatibility with Document.input_namespaces
      # @return [Hash]
      def to_input_namespaces_hash
        result = {}
        @by_prefix.each do |prefix, decls|
          decls.each do |d|
            key = prefix == :default ? :default : prefix
            result[key] = {
              uri: d.uri,
              prefix: d.prefix,
              format: d.format,
              canonical_uri: d.canonical_uri,
              original_uri: d.original_uri,
            }
          end
        end
        result
      end

      # Build from a plain hash (backward compat for Document.input_namespaces)
      # @param hash [Hash] Legacy input_namespaces hash
      # @param declared_at_path [Array<String>] Path where these declarations were found
      # @return [ParsedNamespaceSet]
      def self.from_hash(hash, declared_at_path: [])
        decls = hash.map do |prefix_key, config|
          prefix = prefix_key == :default ? nil : prefix_key.to_s
          ParsedNamespaceDeclaration.new(
            uri: config[:uri],
            prefix: prefix,
            format: config[:format] || (prefix ? :prefix : :default),
            declared_at_path: declared_at_path,
            canonical_uri: config[:canonical_uri],
            original_uri: config[:original_uri],
          )
        end
        new(decls)
      end

      # @return [Boolean]
      def empty?
        @by_prefix.empty?
      end

      # @yield [declaration] Yields each unique declaration
      # @return [self]
      def each(&)
        @by_prefix.values.flatten.uniq.each(&)
        self
      end

      # @return [Integer]
      def size
        @by_prefix.values.flatten.uniq.size
      end
    end
  end
end
