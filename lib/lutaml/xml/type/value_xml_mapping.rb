# frozen_string_literal: true

module Lutaml
  module Xml
    module Type
      # XML mapping configuration for Type::Value classes
      #
      # This class holds the XML configuration for value types,
      # including namespace and XSD type information.
      #
      # @example Creating a custom XML mapping
      #   mapping = ValueXmlMapping.new
      #   mapping.namespace(MyNamespace)
      #   mapping.xsd_type(:string)
      #
      class ValueXmlMapping
        include Lutaml::Xml::SharedDsl

        attr_reader :namespace_class, :xsd_type_name

        def initialize
          @namespace_class = nil
          @xsd_type_name = nil
        end

        # Set the namespace for this Value type
        #
        # @param ns_class_or_symbol [Class, Symbol] XmlNamespace class, :blank, or :inherit
        # @return [void]
        #
        # @raise [Lutaml::Xml::Error::InvalidNamespaceError] if invalid namespace class provided
        #
        # @example Setting namespace with XmlNamespace class
        #   mapping.namespace(MyNamespace)
        #
        # @example Setting blank namespace
        #   mapping.namespace(:blank)
        #
        # @example Inheriting parent namespace
        #   mapping.namespace(:inherit)
        def namespace(ns_class_or_symbol)
          validate_namespace_class!(ns_class_or_symbol)
          @namespace_class = ns_class_or_symbol
        end

        # Get the namespace URI for this mapping
        #
        # @return [String, nil] the namespace URI
        def namespace_uri
          @namespace_class&.uri
        end

        # Get the namespace prefix for this mapping
        #
        # @return [String, nil] the namespace prefix
        def namespace_prefix
          @namespace_class&.prefix_default
        end

        # Set the XSD type name
        #
        # @param type [Symbol, Class] XSD type symbol or Type class
        # @return [void]
        #
        # @example Setting XSD type with Symbol
        #   mapping.xsd_type(:string)  # becomes 'xs:string'
        #
        # @example Setting XSD type with Type class
        #   mapping.xsd_type(Lutaml::Model::Type::String)
        def xsd_type(type)
          @xsd_type_name = resolve_xsd_type(type)
        end

        # Create a deep duplicate of this mapping
        #
        # Used for inheritance when a child type needs its own copy
        # of the parent's XML configuration.
        #
        # @return [ValueXmlMapping] a new mapping with copied values
        def deep_dup
          self.class.new.tap do |dup|
            # namespace_class is a class reference, no need to deep copy
            dup.instance_variable_set(:@namespace_class, @namespace_class)
            # xsd_type_name is a string, Duplicate for safety
            dup.instance_variable_set(:@xsd_type_name, @xsd_type_name.dup) if @xsd_type_name
          end
        end
      end
    end
  end
end
