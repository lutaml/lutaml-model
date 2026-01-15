# frozen_string_literal: true

require_relative "namespace_inheritance_strategy"

module Lutaml
  module Model
    module Xml
      # Strategy for elementFormDefault="unqualified" (W3C DEFAULT)
      # Child elements are in blank namespace
      #
      # This implements W3C XML Schema default behavior when a schema does NOT
      # declare elementFormDefault or declares elementFormDefault="unqualified".
      # Locally declared elements are NOT in the target namespace by default.
      #
      # Exception: Complex types (models) may optionally inherit based on
      # configuration via native_types_inherit setting.
      #
      # @see https://www.w3.org/TR/xmlschema-1/#element-formdefault
      # @see Section 3.3.2: Default is "unqualified"
      class UnqualifiedInheritanceStrategy < NamespaceInheritanceStrategy
        # Children do NOT inherit parent namespace (W3C default)
        #
        # @param element_type [Symbol] :model (complex type) or :native_value (simple type)
        # @param parent_ns_decl [NamespaceDeclaration] parent's namespace declaration
        # @param mapping [Xml::Mapping] the mapping being evaluated
        # @return [Boolean] false - children in blank namespace
        def inherits?(element_type:, parent_ns_decl:, mapping:)
          # W3C Rule: elementFormDefault="unqualified" means children in blank namespace
          # This is the W3C DEFAULT behavior when elementFormDefault is not specified
          #
          # Children must explicitly declare xmlns="" to prevent inheriting
          # the default namespace declaration from parent element
          false
        end
      end
    end
  end
end