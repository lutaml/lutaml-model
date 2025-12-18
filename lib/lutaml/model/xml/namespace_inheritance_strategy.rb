# frozen_string_literal: true

module Lutaml
  module Model
    module Xml
      # Base class for namespace inheritance strategies
      # Determines if child elements inherit parent namespace based on W3C rules
      #
      # W3C XML Schema defines elementFormDefault attribute which controls
      # whether locally declared elements are in the target namespace by default.
      # - "unqualified" (W3C default): children in blank namespace
      # - "qualified": children inherit parent namespace
      #
      # @see https://www.w3.org/TR/xmlschema-1/#element-formdefault
      class NamespaceInheritanceStrategy
        # Determine if child element should inherit parent namespace
        #
        # @param element_type [Symbol] :model (complex type) or :native_value (simple type)
        # @param parent_ns_decl [NamespaceDeclaration] parent's namespace declaration
        # @param mapping [Xml::Mapping] the mapping being evaluated
        # @return [Boolean] true if child should inherit parent namespace
        def inherits?(element_type:, parent_ns_decl:, mapping:)
          raise NotImplementedError, "#{self.class} must implement #inherits?"
        end
      end
    end
  end
end