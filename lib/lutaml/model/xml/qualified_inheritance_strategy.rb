# frozen_string_literal: true

require_relative "namespace_inheritance_strategy"

module Lutaml
  module Model
    module Xml
      # Strategy for elementFormDefault="qualified"
      # All child elements inherit parent namespace
      #
      # This implements W3C XML Schema behavior when a schema declares
      # elementFormDefault="qualified", meaning all locally declared elements
      # are in the target namespace by default.
      #
      # @see https://www.w3.org/TR/xmlschema-1/#element-formdefault
      class QualifiedInheritanceStrategy < NamespaceInheritanceStrategy
        # All elements inherit parent namespace when qualified
        #
        # @param element_type [Symbol] :model or :native_value (not used in this strategy)
        # @param parent_ns_decl [NamespaceDeclaration] parent's namespace declaration
        # @param mapping [Xml::Mapping] the mapping being evaluated (not used in this strategy)
        # @return [Boolean] always true - all children inherit
        def inherits?(element_type:, parent_ns_decl:, mapping:)
          # W3C Rule: elementFormDefault="qualified" means ALL children inherit
          # regardless of whether they are complex types (models) or simple types (values)
          true
        end
      end
    end
  end
end