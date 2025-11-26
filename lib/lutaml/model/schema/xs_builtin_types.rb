module Lutaml
  module Model
    module Schema
      # W3C XML Schema 1.1 Part 2: Datatypes
      # https://www.w3.org/TR/xmlschema11-2/
      #
      # This module defines all built-in XSD types for validation purposes.
      # Used by XSD generation and validation to identify standard W3C types.
      module XsBuiltinTypes
        # Primitive types (Section 3.2)
        # These are the fundamental types from which all other types are derived
        PRIMITIVE_TYPES = %w[
          xs:string
          xs:boolean
          xs:decimal
          xs:float
          xs:double
          xs:duration
          xs:dateTime
          xs:time
          xs:date
          xs:gYearMonth
          xs:gYear
          xs:gMonthDay
          xs:gDay
          xs:gMonth
          xs:hexBinary
          xs:base64Binary
          xs:anyURI
          xs:QName
          xs:NOTATION
        ].freeze

        # Derived types (Section 3.3)
        # These are built from primitive types with restrictions
        DERIVED_TYPES = %w[
          xs:normalizedString
          xs:token
          xs:language
          xs:NMTOKEN
          xs:NMTOKENS
          xs:Name
          xs:NCName
          xs:ID
          xs:IDREF
          xs:IDREFS
          xs:ENTITY
          xs:ENTITIES
          xs:integer
          xs:nonPositiveInteger
          xs:negativeInteger
          xs:long
          xs:int
          xs:short
          xs:byte
          xs:nonNegativeInteger
          xs:unsignedLong
          xs:unsignedInt
          xs:unsignedShort
          xs:unsignedByte
          xs:positiveInteger
          xs:yearMonthDuration
          xs:dayTimeDuration
          xs:dateTimeStamp
        ].freeze

        # Special types
        # xs:anyType - The root of the type hierarchy
        # xs:anySimpleType - The base type for all simple types
        SPECIAL_TYPES = %w[
          xs:anyType
          xs:anySimpleType
        ].freeze

        # All built-in types
        ALL_TYPES = (PRIMITIVE_TYPES + DERIVED_TYPES + SPECIAL_TYPES).freeze

        # Check if a type name is a W3C XML Schema built-in type
        #
        # @param type_name [String] The XSD type name to check (e.g., "xs:string")
        # @return [Boolean] true if the type is a standard W3C built-in type
        #
        # @example
        #   XsBuiltinTypes.builtin?("xs:string")  #=> true
        #   XsBuiltinTypes.builtin?("xs:integer") #=> true
        #   XsBuiltinTypes.builtin?("CustomType") #=> false
        def self.builtin?(type_name)
          ALL_TYPES.include?(type_name)
        end

        # Get the category of a built-in type
        #
        # @param type_name [String] The XSD type name
        # @return [Symbol, nil] :primitive, :derived, :special, or nil if not built-in
        #
        # @example
        #   XsBuiltinTypes.category("xs:string")  #=> :primitive
        #   XsBuiltinTypes.category("xs:integer") #=> :derived
        #   XsBuiltinTypes.category("CustomType") #=> nil
        def self.category(type_name)
          return :primitive if PRIMITIVE_TYPES.include?(type_name)
          return :derived if DERIVED_TYPES.include?(type_name)
          return :special if SPECIAL_TYPES.include?(type_name)

          nil
        end
      end
    end
  end
end