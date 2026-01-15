# frozen_string_literal: true

require_relative "namespace_declaration_data"

module Lutaml
  module Model
    module Xml
      # Represents a single namespace declaration in an XML element
      #
      # REFACTORED (Session 176):
      # Stores DATA only, NO XML strings
      # Accepts NamespaceDeclarationData in constructor
      # Adapters build xmlns strings from this data
      #
      # CRITICAL ARCHITECTURAL PRINCIPLE:
      # This class stores WHAT and HOW (data decisions)
      # Adapters build the actual xmlns="uri" or xmlns:prefix="uri" strings
      #
      # @example Default namespace declaration
      #   data = NamespaceDeclarationData.new(
      #     namespace_class: MyNamespace,
      #     format: :default,
      #     declared_at: :here
      #   )
      #   decl = NamespaceDeclaration.new(data)
      #
      # @example Prefixed namespace declaration
      #   data = NamespaceDeclarationData.new(
      #     namespace_class: MyNamespace,
      #     format: :prefix,
      #     declared_at: :inherited
      #   )
      #   decl = NamespaceDeclaration.new(data)
      #
      class NamespaceDeclaration
        # @return [Class] The XmlNamespace class for this declaration
        attr_reader :ns_object

        # @return [Symbol] Format of declaration (:default or :prefix)
        attr_reader :format

        # @return [Symbol] Where this declaration is made
        #   - :here - declared at this element
        #   - :inherited - inherited from parent
        #   - :local_on_use - should be declared locally when used
        attr_reader :declared_at

        # @return [Symbol, nil] Source of this declaration (:input for parsed XML)
        attr_reader :source

        # @return [String, nil] Custom prefix override from options[:prefix]
        attr_reader :prefix_override

        # Initialize from NamespaceDeclarationData
        #
        # @param data [NamespaceDeclarationData] Declaration data
        def initialize(data)
          unless data.is_a?(NamespaceDeclarationData)
            raise ArgumentError, "Expected NamespaceDeclarationData, got #{data.class}"
          end

          @ns_object = data.namespace_class
          @format = data.format
          @declared_at = data.declared_at
          @source = data.source
          @prefix_override = data.prefix_override
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

        # Get element_form_default setting
        #
        # @return [Symbol] :qualified or :unqualified
        def element_form_default
          if @ns_object.respond_to?(:element_form_default)
            @ns_object.element_form_default
          else
            :qualified  # W3C default
          end
        end

        # Get attribute_form_default setting
        #
        # @return [Symbol] :qualified or :unqualified
        def attribute_form_default
          if @ns_object.respond_to?(:attribute_form_default)
            @ns_object.attribute_form_default
          else
            :unqualified  # W3C default
          end
        end

        # Create a copy with updated attributes
        #
        # @param attrs [Hash] Attributes to update
        # @return [NamespaceDeclaration] New instance with merged attributes
        def merge(attrs)
          # Create new NamespaceDeclarationData with merged attributes
          data = NamespaceDeclarationData.new(
            namespace_class: attrs[:ns_object] || @ns_object,
            format: attrs[:format] || @format,
            declared_at: attrs[:declared_at] || @declared_at,
            source: attrs.key?(:source) ? attrs[:source] : @source,
            prefix_override: attrs.key?(:prefix_override) ? attrs[:prefix_override] : @prefix_override
          )
          NamespaceDeclaration.new(data)
        end

        # Convert to hash for debugging
        #
        # @return [Hash] Hash representation
        def to_h
          {
            ns_object: @ns_object,
            format: @format,
            declared_at: @declared_at,
            source: @source,
            prefix_override: @prefix_override,
          }.compact
        end

        # String representation for debugging
        #
        # @return [String]
        def inspect
          "#<NamespaceDeclaration #{@ns_object} format=#{@format} declared_at=#{@declared_at}>"
        end

        # Backward compatibility: Build xmlns declaration string
        # (Legacy API from pre-Session 176 refactoring)
        #
        # @return [String] The xmlns attribute string (e.g., "xmlns=\"uri\"" or "xmlns:prefix=\"uri\"")
        def xmlns_declaration
          if @format == :default
            "xmlns=\"#{uri}\""
          else
            pfx = prefix
            "xmlns:#{pfx}=\"#{uri}\""
          end
        end
      end
    end
  end
end