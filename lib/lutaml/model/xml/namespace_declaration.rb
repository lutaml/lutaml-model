# frozen_string_literal: true

module Lutaml
  module Model
    module Xml
      # Represents a single namespace declaration in an XML element
      #
      # This class encapsulates all information about how a namespace should be
      # declared at a specific element in the XML tree.
      #
      # @example Default namespace declaration
      #   decl = NamespaceDeclaration.new(
      #     ns_object: MyNamespace,
      #     format: :default,
      #     xmlns_declaration: 'xmlns="http://example.com"',
      #     declared_at: :here
      #   )
      #
      # @example Prefixed namespace declaration
      #   decl = NamespaceDeclaration.new(
      #     ns_object: MyNamespace,
      #     format: :prefix,
      #     xmlns_declaration: 'xmlns:ex="http://example.com"',
      #     declared_at: :inherited
      #   )
      class NamespaceDeclaration
        # @return [Class] The XmlNamespace class for this declaration
        attr_reader :ns_object

        # @return [Symbol] Format of declaration (:default or :prefix)
        attr_reader :format

        # @return [String] The actual xmlns declaration string
        attr_reader :xmlns_declaration

        # @return [Symbol] Where this declaration is made
        #   - :here - declared at this element
        #   - :inherited - inherited from parent
        #   - :local_on_use - should be declared locally when used
        attr_reader :declared_at

        # @return [Symbol, nil] Source of this declaration (:input for parsed XML)
        attr_reader :source

        # @return [String, nil] Custom prefix override from options[:prefix]
        attr_reader :prefix_override

        # Initialize a namespace declaration
        #
        # @param ns_object [Class] XmlNamespace class
        # @param format [Symbol] :default or :prefix
        # @param xmlns_declaration [String] The xmlns attribute string
        # @param declared_at [Symbol] :here, :inherited, or :local_on_use
        # @param source [Symbol, nil] Optional source marker (e.g., :input)
        # @param prefix_override [String, nil] Optional custom prefix override
        def initialize(ns_object:, format:, xmlns_declaration:, declared_at:, source: nil, prefix_override: nil)
          @ns_object = ns_object
          @format = format
          @xmlns_declaration = xmlns_declaration
          @declared_at = declared_at
          @source = source
          @prefix_override = prefix_override
        end

        # Get the namespace key for lookups
        #
        # @return [String] The namespace key
        def key
          @ns_object.to_key
        end

        # Get the namespace URI
        #
        # @return [String] The namespace URI
        def uri
          @ns_object.uri
        end

        # Get the namespace prefix (if any)
        #
        # @return [String, nil] The namespace prefix (override if present, otherwise default)
        def prefix
          @prefix_override || @ns_object.prefix_default
        end

        # Check if this declaration uses default format
        #
        # @return [Boolean] true if format is :default
        def default_format?
          @format == :default
        end

        # Check if this declaration uses prefix format
        #
        # @return [Boolean] true if format is :prefix
        def prefix_format?
          @format == :prefix
        end

        # Check if this declaration is made at this element
        #
        # @return [Boolean] true if declared_at is :here
        def declared_here?
          @declared_at == :here
        end

        # Check if this declaration is inherited from parent
        #
        # @return [Boolean] true if declared_at is :inherited
        def inherited?
          @declared_at == :inherited
        end

        # Check if this declaration should be made locally on use
        #
        # @return [Boolean] true if declared_at is :local_on_use
        def local_on_use?
          @declared_at == :local_on_use
        end

        # Check if this declaration came from input XML
        #
        # @return [Boolean] true if source is :input
        def from_input?
          @source == :input
        end

        # Create a copy with updated attributes
        #
        # @param attrs [Hash] Attributes to update
        # @return [NamespaceDeclaration] New instance with merged attributes
        def merge(attrs)
          NamespaceDeclaration.new(
            ns_object: attrs[:ns_object] || @ns_object,
            format: attrs[:format] || @format,
            xmlns_declaration: attrs[:xmlns_declaration] || @xmlns_declaration,
            declared_at: attrs[:declared_at] || @declared_at,
            source: attrs.key?(:source) ? attrs[:source] : @source,
            prefix_override: attrs.key?(:prefix_override) ? attrs[:prefix_override] : @prefix_override
          )
        end

        # Convert to hash for backward compatibility
        #
        # @return [Hash] Hash representation
        def to_h
          {
            ns_object: @ns_object,
            format: @format,
            xmlns_declaration: @xmlns_declaration,
            declared_at: @declared_at,
            source: @source,
            prefix_override: @prefix_override,
          }.compact
        end

        # Create from hash (for backward compatibility during migration)
        #
        # @param hash [Hash] Hash with declaration data
        # @return [NamespaceDeclaration] New instance
        def self.from_hash(hash)
          new(
            ns_object: hash[:ns_object],
            format: hash[:format],
            xmlns_declaration: hash[:xmlns_declaration],
            declared_at: hash[:declared_at],
            source: hash[:source],
            prefix_override: hash[:prefix_override]
          )
        end
      end
    end
  end
end