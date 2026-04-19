# frozen_string_literal: true

module Lutaml
  module Xml
    module TypeNamespace
      # Value object representing a reference to a type namespace
      #
      # Type namespaces are declared on attribute types via xml_namespace.
      # This reference tracks the attribute, rule, and context for later resolution.
      class Reference
        attr_reader :attribute, :rule, :context, :mapper_class

        # @param attribute [Attribute] The attribute definition
        # @param rule [MappingRule] The mapping rule
        # @param context [Symbol] :attribute or :element
        # @param mapper_class [Class, nil] The model class that owns this attribute
        def initialize(attribute, rule, context, mapper_class: nil)
          unless %i[
            attribute element
          ].include?(context)
            raise ArgumentError,
                  "Context must be :attribute or :element"
          end

          @attribute = attribute
          @rule = rule
          @context = context
          @mapper_class = mapper_class
          freeze
        end

        # Get the type class from the attribute, resolving the register context
        # from the mapper_class if available.
        #
        # @param register [Object] The type register
        # @return [Class, nil] The type class
        def type_class(register)
          resolved = if @mapper_class
                       Lutaml::Model::Register.resolve_for_child(@mapper_class,
                                                                 register)
                     else
                       register
                     end
          @attribute.type(resolved)
        end

        # Get the namespace class from the type, resolving the register context
        # from the mapper_class if available.
        #
        # @param register [Object] The type register
        # @return [XmlNamespace, nil] The namespace class
        def namespace_class(register)
          type = type_class(register)
          return nil unless type.is_a?(Class) && type <= Lutaml::Model::Type::Value

          type.namespace_class
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
