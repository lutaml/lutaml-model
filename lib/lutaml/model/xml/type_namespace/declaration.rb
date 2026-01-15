# frozen_string_literal: true

module Lutaml
  module Model
    module Xml
      module TypeNamespace
        # Value object representing a type namespace declaration
        #
        # Type namespaces are declared on PARENT elements and used by
        # CHILD elements as prefixes.
        class Declaration
          VALID_DECLARED_AT_VALUES = [:root, :parent, :inline].freeze

          attr_reader :namespace_class, :prefix, :declared_at, :element_name

          # @param namespace_class [XmlNamespace] The namespace class
          # @param prefix [String] The prefix to use
          # @param declared_at [Symbol] :root, :parent, or :inline
          # @param element_name [String, nil] The element name (for debugging)
          def initialize(namespace_class:, prefix:, declared_at:, element_name: nil)
            unless VALID_DECLARED_AT_VALUES.include?(declared_at)
              raise ArgumentError, "declared_at must be :root, :parent, or :inline, got: #{declared_at.inspect}"
            end
            @namespace_class = namespace_class
            @prefix = prefix
            @declared_at = declared_at
            @element_name = element_name
            freeze
          end

          # Check if declared at root
          def root_level?
            @declared_at == :root
          end

          # Check if declared at parent
          def parent_level?
            @declared_at == :parent
          end

          # Check if declared inline
          def inline?
            @declared_at == :inline
          end

          # Get the xmlns attribute string
          #
          # @return [String] The xmlns declaration (e.g., "xmlns:dc=...")
          def to_xmlns_attribute
            "xmlns:#{@prefix}=#{@namespace_class.uri}"
          end

          def to_s
            "TypeNamespaceDeclaration: #{@prefix}=#{@namespace_class.uri} (#{@declared_at})"
          end
        end
      end
    end
  end
end
