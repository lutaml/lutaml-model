# frozen_string_literal: true

require_relative 'declaration'

module Lutaml
  module Model
    module Xml
      module TypeNamespace
        # Resolves type namespace prefixes for elements
        #
        # Type namespaces are declared on parent elements and used as
        # prefixes on child elements. This resolver determines which
        # prefix to use for a given type namespace.
        class Resolver
          # Get the prefix for a type namespace on an element
          #
          # @param type_namespace_class [XmlNamespace] The type namespace class
          # @param declaration_plan [DeclarationPlan] The declaration plan
          # @return [String, nil] The prefix, or nil if not declared
          def prefix_for(type_namespace_class, declaration_plan)
            return nil unless type_namespace_class
            return nil unless declaration_plan

            # Look up namespace in plan
            ns_info = declaration_plan.namespace_for_class(type_namespace_class)
            return nil unless ns_info

            # Return the prefix
            ns_info[:prefix]
          end

          # Check if a type namespace needs to be declared
          #
          # @param type_namespace_class [XmlNamespace] The type namespace class
          # @param element_namespace_class [XmlNamespace, nil] The element's namespace
          # @return [Boolean] true if declaration needed
          def needs_declaration?(type_namespace_class, element_namespace_class)
            return true unless element_namespace_class

            # If element and type have same namespace, element handles it
            type_namespace_class != element_namespace_class
          end
        end
      end
    end
  end
end
