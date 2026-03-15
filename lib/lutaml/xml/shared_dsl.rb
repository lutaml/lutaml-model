# frozen_string_literal: true

module Lutaml
  module Xml
    # Shared DSL methods for XML configuration
    #
    # This module provides common DSL methods used by both Model classes
    # (via Lutaml::Xml::Mapping) and Type classes (via Lutaml::Model::Type::ValueXmlMapping).
    #
    # @example Including in a class
    #   class MyMapping
    #     include Lutaml::Xml::SharedDsl
    #
    #     def namespace(ns_class)
    #       validate_namespace_class!(ns_class)
    #       @namespace_class = ns_class
    #     end
    #   end
    #
    module SharedDsl
      # Validate that a namespace class is valid
      #
      # @param ns_class [Class, Symbol, nil] the namespace class or symbol to validate
      # @raise [Lutaml::Model::InvalidNamespaceError] if invalid
      #
      # @example Validating an XmlNamespace class
      #   validate_namespace_class!(MyNamespace)  # passes if MyNamespace < Lutaml::Xml::Namespace
      #
      # @example Validating special symbols
      #   validate_namespace_class!(:blank)   # passes
      #   validate_namespace_class!(:inherit) # passes
      def validate_namespace_class!(ns_class)
        return if ns_class.nil?
        return if %i[blank inherit].include?(ns_class)

        # Use ::Class to refer to Ruby built-in Class (avoiding Lutaml::Model::Type::Class)
        valid = ns_class.is_a?(::Class) && defined?(::Lutaml::Xml::Namespace) && ns_class < ::Lutaml::Xml::Namespace
        unless valid
          raise Lutaml::Xml::Error::InvalidNamespaceError.new(
            expected: "XmlNamespace class, :inherit, or :blank",
            got: ns_class,
          )
        end
      end

      # Resolve XSD type from various input formats
      #
      # @param type [Symbol, Class] the type to resolve
      # @return [String] the resolved XSD type name
      #
      # @example Resolving from symbol
      #   resolve_xsd_type(:string)  # => "xs:string"
      #   resolve_xsd_type(:integer) # => "xs:integer"
      #
      # @example Resolving from Type class
      #   resolve_xsd_type(Lutaml::Model::Type::String)  # => "xs:string"
      def resolve_xsd_type(type)
        # Use ::Symbol and ::Class to refer to Ruby built-in classes
        case type
        when ::Symbol
          resolve_xsd_type_from_symbol(type)
        when ::Class
          resolve_xsd_type_from_class(type)
        else
          raise ArgumentError,
                "xsd_type must be a Symbol or Class, got #{type.class}"
        end
      end

      # Valid XSD type symbols for shorthand notation
      VALID_XSD_TYPE_SYMBOLS = %i[
        string
        integer
        float
        double
        decimal
        boolean
        date
        time
        datetime
        duration
        anyuri
        qname
        base64binary
        hexbinary
      ].freeze

      # Resolve XSD type from a symbol
      #
      # @param sym [Symbol] the type symbol
      # @return [String] the XSD type name
      # @raise [ArgumentError] if unknown type symbol
      def resolve_xsd_type_from_symbol(sym)
        unless VALID_XSD_TYPE_SYMBOLS.include?(sym)
          raise ArgumentError,
                "Unknown type symbol: #{sym.inspect}. " \
                "Valid symbols: #{VALID_XSD_TYPE_SYMBOLS.join(', ')}"
        end

        "xs:#{sym}"
      end

      # Resolve XSD type from a class
      #
      # @param klass [Class] the type class
      # @return [String] the XSD type name
      # @raise [ArgumentError] if class doesn't inherit from Type::Value
      def resolve_xsd_type_from_class(klass)
        unless klass.is_a?(::Class) && klass < Lutaml::Model::Type::Value
          raise ArgumentError,
                "xsd_type class must inherit from Lutaml::Model::Type::Value, " \
                "got #{klass.inspect}"
        end

        klass.default_xsd_type
      end
    end
  end
end
