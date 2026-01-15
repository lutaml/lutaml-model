# frozen_string_literal: true

require_relative "../xml_namespace"

module Lutaml
  module Model
    module Xml
      # Special namespace class representing the blank namespace (xmlns="")
      #
      # Used when elements explicitly need to opt out of their parent's
      # default namespace per W3C XML namespace semantics.
      #
      # When a parent element uses default namespace format (xmlns="uri")
      # and a child element should be in the blank namespace, the child
      # must explicitly declare xmlns="" to prevent inheriting the parent's
      # default namespace.
      #
      # @example Parent with default namespace, child needs blank
      #   <root xmlns="http://example.com/ns">
      #     <child xmlns="">Value</child>
      #   </root>
      #
      class BlankNamespace < Lutaml::Model::XmlNamespace
        # Blank namespace has empty URI
        uri ""

        # @return [String] Unique key for namespace tracking
        def self.to_key
          "blank"
        end

        # Blank namespace has no prefix
        #
        # @return [nil] Always nil for blank namespace
        def self.prefix_default
          nil
        end

        # Blank namespace is always unqualified
        #
        # @return [Symbol] Always :unqualified
        def self.element_form_default
          :unqualified
        end

        # Blank namespace has no attribute form default
        #
        # @return [Symbol] Always :unqualified
        def self.attribute_form_default
          :unqualified
        end
      end
    end
  end
end