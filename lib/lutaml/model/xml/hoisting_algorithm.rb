# frozen_string_literal: true

module Lutaml
  module Model
    module Xml
      # HoistingAlgorithm defines strategies for namespace declaration placement.
      #
      # When serializing XML, we must decide WHERE to declare each namespace.
      # This module provides swappable algorithms for different hoisting strategies.
      #
      # Key concepts:
      # - namespace_scope makes namespaces ELIGIBLE for hoisting to any parent
      # - The algorithm determines WHERE eligible namespaces are actually declared
      # - Round-trip preservation takes priority (use stored plan if available)
      #
      # Algorithm selection priority:
      # 1. PRESERVED - if stored plan exists (round-trip fidelity)
      # 2. User option - to_xml(hoisting: :lca)
      # 3. Class config - xml { hoisting_algorithm :first_usage }
      # 4. Global default - Config.default_hoisting_algorithm
      #
      module HoistingAlgorithm
        # Base class for hoisting algorithms
        #
        # Subclasses implement should_hoist_here? to determine if a namespace
        # should be declared at a given element.
        #
        class Base
          # Determine if namespace should be declared at this element
          #
          # @param element [XmlDataModel::XmlElement] Current element
          # @param namespace_class [Class] Namespace class to check
          # @param needs [NamespaceNeeds] All namespace needs
          # @param context [Hash] Context including:
          #   - :is_root [Boolean] Whether this is root element
          #   - :parent_hoisted [Hash] Namespaces already declared on ancestors
          #   - :stored_plan [DeclarationPlan, nil] Stored plan from parsing
          # @return [Boolean] true if namespace should be declared here
          def should_hoist_here?(element, namespace_class, needs, context)
            raise NotImplementedError, "Subclasses must implement should_hoist_here?"
          end

          protected

          # Check if element or its descendants use a namespace
          def element_needs_namespace?(element, namespace_class)
            return false unless element.respond_to?(:children)

            element.children.each do |child|
              next unless child.is_a?(Lutaml::Model::XmlDataModel::XmlElement)

              return true if child.namespace_class == namespace_class

              child.attributes.each do |attr|
                return true if attr.namespace_class == namespace_class
              end

              return true if element_needs_namespace?(child, namespace_class)
            end

            false
          end

          # Check if namespace is already declared on an ancestor
          def already_hoisted?(namespace_class, context)
            parent_hoisted = context[:parent_hoisted] || {}
            parent_hoisted.values.include?(namespace_class.uri)
          end
        end

        # LCA (Lowest Common Ancestor) Algorithm
        #
        # Declares namespace at the smallest subtree covering all usages.
        # This is more compact XML but wider namespace scope.
        #
        # @example
        #   <parent xmlns:ns="...">     <!-- LCA of child1 and child2 -->
        #     <ns:child1>...</ns:child1>
        #     <ns:child2>...</ns:child2>
        #   </parent>
        #
        class LCA < Base
          def should_hoist_here?(element, namespace_class, needs, context)
            return false if already_hoisted?(namespace_class, context)

            element_needs_namespace?(element, namespace_class)
          end
        end

        # FirstUsage Algorithm
        #
        # Declares namespace only at the literal first element that uses it.
        # No hoisting - each element declares its own namespace.
        #
        # @example
        #   <parent>
        #     <ns:child1 xmlns:ns="...">...</ns:child1>
        #     <ns:child2 xmlns:ns="...">...</ns:child2>  <!-- Repeated -->
        #   </parent>
        #
        class FirstUsage < Base
          def should_hoist_here?(element, namespace_class, needs, context)
            return false if already_hoisted?(namespace_class, context)

            # Only declare if this element DIRECTLY uses the namespace
            element.namespace_class == namespace_class ||
              element.attributes.any? { |a| a.namespace_class == namespace_class }
          end
        end

        # NamespaceScopeOnly Algorithm
        #
        # Only hoists namespaces that are in namespace_scope.
        # Non-scope namespaces are declared at first usage.
        #
        # This is the strictest interpretation of namespace_scope semantics.
        #
        class NamespaceScopeOnly < Base
          def should_hoist_here?(element, namespace_class, needs, context)
            return false if already_hoisted?(namespace_class, context)

            scope_config = needs.scope_config_for(namespace_class)

            if scope_config
              # In namespace_scope - eligible for hoisting, use LCA logic
              element_needs_namespace?(element, namespace_class)
            else
              # Not in namespace_scope - only at first usage
              element.namespace_class == namespace_class ||
                element.attributes.any? { |a| a.namespace_class == namespace_class }
            end
          end
        end

        # Preserved Algorithm
        #
        # Uses hoisting locations from stored DeclarationPlan.
        # Critical for round-trip fidelity - changing hoist locations could break readers.
        #
        # If no stored plan or element not found, falls back to provided fallback algorithm.
        #
        class Preserved < Base
          attr_reader :fallback

          # @param fallback [Base] Algorithm to use when no stored location exists
          def initialize(fallback: LCA.new)
            @fallback = fallback
          end

          def should_hoist_here?(element, namespace_class, needs, context)
            stored_plan = context[:stored_plan]

            if stored_plan && stored_location_exists?(stored_plan, element, namespace_class)
              # Use stored location
              stored_declares_here?(stored_plan, element, namespace_class)
            else
              # Fall back to configured algorithm
              fallback.should_hoist_here?(element, namespace_class, needs, context)
            end
          end

          private

          def stored_location_exists?(stored_plan, element, namespace_class)
            # Check if stored plan has information about this namespace
            # TODO: Implement tree traversal to find matching element
            false # For now, always fall back
          end

          def stored_declares_here?(stored_plan, element, namespace_class)
            # Check if stored plan declares this namespace at this element
            # TODO: Implement tree traversal to check hoisted_declarations
            false
          end
        end

        # Registry of available algorithms
        ALGORITHMS = {
          lca: LCA,
          first_usage: FirstUsage,
          namespace_scope_only: NamespaceScopeOnly,
          preserved: Preserved,
        }.freeze

        # Get algorithm instance by name
        #
        # @param name [Symbol] Algorithm name (:lca, :first_usage, etc.)
        # @param options [Hash] Options to pass to algorithm constructor
        # @return [Base] Algorithm instance
        def self.get(name, **options)
          klass = ALGORITHMS[name]
          raise ArgumentError, "Unknown hoisting algorithm: #{name}" unless klass

          if klass == Preserved && options[:fallback]
            fallback = get(options[:fallback])
            klass.new(fallback: fallback)
          else
            klass.new
          end
        end

        # Default algorithm
        def self.default
          LCA.new
        end
      end
    end
  end
end
