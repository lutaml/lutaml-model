# frozen_string_literal: true

module Lutaml
  module Model
    module Xml
      # BlankNamespaceHandler - Handle W3C xmlns="" blank namespace compliance
      #
      # Extracts logic for determining when to add xmlns="" declaration based on W3C
      # XML Namespaces 1.0 §6.2 semantics.
      #
      # @example Usage in adapter
      #   if BlankNamespaceHandler.needs_xmlns_blank?(mapping: mapping, options: options)
      #     attributes["xmlns"] = ""
      #   end
      module BlankNamespaceHandler
        # Determine if element needs xmlns="" declaration
        #
        # Per W3C XML Namespaces 1.0 §6.2, xmlns="" explicitly declares the blank namespace.
        # This is ONLY for elements with explicit namespace: :blank declaration.
        # Elements with nil namespace (unqualified) silently inherit parent's namespace.
        #
        # @param mapping [Mapping] the XML mapping for the element
        # @param options [Hash] serialization options
        # @return [Boolean] true if xmlns="" should be added
        def self.needs_xmlns_blank?(mapping:, options:)
          parent_uses_default_ns = options[:parent_uses_default_ns]
          parent_element_form_default = options[:parent_element_form_default]

          # Case 1: Element has EXPLICIT :blank namespace
          # Must explicitly declare xmlns="" to remove parent's default namespace
          if mapping.namespace_class == :blank && parent_uses_default_ns
            return true
          end

          # Case 2: W3C compliance for unqualified children
          # Unqualified children need xmlns="" when parent uses default format
          # This prevents children from inheriting parent's default namespace
          if mapping.namespace_class.nil? &&
             parent_uses_default_ns &&
             parent_element_form_default == :qualified
            return true
          end

          false
        end
      end
    end
  end
end