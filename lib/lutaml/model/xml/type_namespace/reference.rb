# frozen_string_literal: true

module Lutaml
  module Model
    module Xml
      module TypeNamespace
        # Value object representing a reference to a type namespace
        #
        # Type namespaces are declared on attribute types via xml_namespace.
        # This reference tracks the attribute, rule, and context for later resolution.
        class Reference
          attr_reader :attribute, :rule, :context

          # @param attribute [Attribute] The attribute definition
          # @param rule [MappingRule] The mapping rule
          # @param context [Symbol] :attribute or :element
          def initialize(attribute, rule, context)
            raise ArgumentError, "Context must be :attribute or :element" unless [:attribute, :element].include?(context)

            @attribute = attribute
            @rule = rule
            @context = context
            freeze
          end

          # Get the type class from the attribute
          #
          # @param register [Object] The type register
          # @return [Class, nil] The type class
          def type_class(register)
            @attribute.type(register)
          end

          # Get the namespace class from the type
          #
          # @param register [Object] The type register
          # @return [XmlNamespace, nil] The namespace class
          def namespace_class(register)
            type = type_class(register)
            return nil unless type&.respond_to?(:xml_namespace)
            type.xml_namespace
          end

          # Check if this is for an attribute context
          def attribute_context?
            @context == :attribute
          end

          # Check if this is for an element context
          def element_context?
            @context == :element
          end
        end
      end
    end
  end
end
