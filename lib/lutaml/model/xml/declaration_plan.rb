# frozen_string_literal: true

require_relative "namespace_declaration"

module Lutaml
  module Model
    module Xml
      # Represents the complete namespace declaration plan for an XML element
      #
      # This class encapsulates all namespace-related decisions for serializing
      # a model element to XML, including:
      # - Which namespaces to declare at this element
      # - Type namespace assignments for attributes
      # - Namespace resolution strategies for elements
      # - Plans for child elements
      #
      # @example Creating a declaration plan
      #   plan = DeclarationPlan.new
      #   plan.add_namespace(ns_class, format: :default, xmlns: 'xmlns="..."', declared_at: :here)
      #   plan.add_type_namespace(:my_attr, TypeNamespace)
      #   plan.set_element_strategy(:my_attr, strategy)
      #
      class DeclarationPlan
        # @return [Hash<String, NamespaceDeclaration>] Namespace declarations by key
        attr_reader :namespaces

        # @return [Hash<Symbol, DeclarationPlan>] Child element plans
        attr_reader :children_plans

        # @return [Hash<Symbol, Class>] Type namespace assignments (attr_name => XmlNamespace class)
        attr_reader :type_namespaces

        # @return [Hash<Symbol, NamespaceResolutionStrategy>] Element namespace strategies
        attr_reader :element_strategies

        # Initialize an empty declaration plan
        def initialize
          @namespaces = {}
          @children_plans = {}
          @type_namespaces = {}
          @element_strategies = {}
        end

        # Add a namespace declaration to this plan
        #
        # @param ns_class [Class] XmlNamespace class
        # @param format [Symbol] :default or :prefix
        # @param xmlns_declaration [String] The xmlns attribute string
        # @param declared_at [Symbol] :here, :inherited, or :local_on_use
        # @param source [Symbol, nil] Optional source marker
        # @param prefix_override [String, nil] Optional custom prefix override
        # @return [NamespaceDeclaration] The created declaration
        def add_namespace(ns_class, format:, xmlns_declaration:, declared_at:, source: nil, prefix_override: nil)
          key = ns_class.to_key
          declaration = NamespaceDeclaration.new(
            ns_object: ns_class,
            format: format,
            xmlns_declaration: xmlns_declaration,
            declared_at: declared_at,
            source: source,
            prefix_override: prefix_override
          )
          @namespaces[key] = declaration
        end

        # Get a namespace declaration by key
        #
        # @param key [String] The namespace key
        # @return [NamespaceDeclaration, nil] The declaration or nil
        def namespace(key)
          @namespaces[key]
        end

        # Get a namespace declaration by XmlNamespace class
        #
        # @param ns_class [Class] XmlNamespace class
        # @return [NamespaceDeclaration, nil] The declaration or nil
        def namespace_for_class(ns_class)
          @namespaces[ns_class.to_key]
        end

        # Update an existing namespace declaration
        #
        # @param key [String] The namespace key
        # @param declaration [NamespaceDeclaration] The new declaration
        # @return [NamespaceDeclaration] The updated declaration
        def update_namespace(key, declaration)
          @namespaces[key] = declaration
        end

        # Check if a namespace is declared in this plan
        #
        # @param key [String] The namespace key
        # @return [Boolean] true if namespace is in plan
        def namespace?(key)
          @namespaces.key?(key)
        end

        # Add a type namespace assignment
        #
        # @param attr_name [Symbol] The attribute name
        # @param ns_class [Class] XmlNamespace class for the type
        # @return [Class] The namespace class
        def add_type_namespace(attr_name, ns_class)
          @type_namespaces[attr_name] = ns_class
        end

        # Get type namespace for an attribute
        #
        # @param attr_name [Symbol] The attribute name
        # @return [Class, nil] XmlNamespace class or nil
        def type_namespace(attr_name)
          @type_namespaces[attr_name]
        end

        # Set namespace resolution strategy for an element
        #
        # @param attr_name [Symbol] The attribute/element name
        # @param strategy [NamespaceResolutionStrategy] The strategy to use
        # @return [NamespaceResolutionStrategy] The strategy
        def set_element_strategy(attr_name, strategy)
          @element_strategies[attr_name] = strategy
        end

        # Get namespace resolution strategy for an element
        #
        # @param attr_name [Symbol] The attribute/element name
        # @return [NamespaceResolutionStrategy, nil] The strategy or nil
        def element_strategy(attr_name)
          @element_strategies[attr_name]
        end

        # Add a child element plan
        #
        # @param child_name [Symbol] The child attribute name
        # @param child_plan [DeclarationPlan] The child's declaration plan
        # @return [DeclarationPlan] The child plan
        def add_child_plan(child_name, child_plan)
          @children_plans[child_name] = child_plan
        end

        # Get child element plan
        #
        # @param child_name [Symbol] The child attribute name
        # @return [DeclarationPlan, nil] The child plan or nil
        def child_plan(child_name)
          @children_plans[child_name]
        end

        # Get all namespace declarations that should be declared at this element
        #
        # @return [Hash<String, NamespaceDeclaration>] Declarations with declared_at == :here
        def declarations_here
          @namespaces.select { |_k, decl| decl.declared_here? }
        end

        # Get all inherited namespace declarations
        #
        # @return [Hash<String, NamespaceDeclaration>] Declarations with declared_at == :inherited
        def inherited_declarations
          @namespaces.select { |_k, decl| decl.inherited? }
        end

        # Get all local_on_use namespace declarations
        #
        # @return [Hash<String, NamespaceDeclaration>] Declarations with declared_at == :local_on_use
        def local_on_use_declarations
          @namespaces.select { |_k, decl| decl.local_on_use? }
        end

        # Inherit namespaces from parent plan
        #
        # Transforms parent's :here declarations to :inherited
        # Keeps :inherited as :inherited
        # Passes through :local_on_use unchanged
        #
        # @param parent_plan [DeclarationPlan] The parent element's plan
        # @return [void]
        def inherit_from(parent_plan)
          return unless parent_plan

          parent_plan.namespaces.each do |key, parent_decl|
            if parent_decl.declared_here?
              # Parent declared this - child inherits it
              @namespaces[key] = parent_decl.merge(declared_at: :inherited)
            elsif parent_decl.inherited?
              # Parent inherited this - child also inherits it
              @namespaces[key] = parent_decl.merge(declared_at: :inherited)
            else
              # :local_on_use - pass through unchanged
              @namespaces[key] = parent_decl.merge(declared_at: parent_decl.declared_at)
            end
          end

          # Also inherit type namespaces
          parent_plan.type_namespaces.each do |attr_name, ns_class|
            @type_namespaces[attr_name] = ns_class
          end

          # CRITICAL: Also inherit element strategies
          # Element strategies are set at parent level but child elements need them
          parent_plan.element_strategies.each do |attr_name, strategy|
            @element_strategies[attr_name] = strategy
          end
        end

        # Convert to hash for backward compatibility
        #
        # @return [Hash] Hash representation matching legacy format
        def to_h
          {
            namespaces: @namespaces.transform_values(&:to_h),
            children_plans: @children_plans.transform_values(&:to_h),
            type_namespaces: @type_namespaces.dup,
            element_strategies: @element_strategies.dup,
          }
        end

        # Create from hash (for backward compatibility during migration)
        #
        # @param hash [Hash] Hash with plan data
        # @return [DeclarationPlan] New plan instance
        def self.from_hash(hash)
          plan = new

          # Convert namespace hashes to NamespaceDeclaration objects
          hash[:namespaces]&.each do |key, ns_hash|
            plan.namespaces[key] = NamespaceDeclaration.from_hash(ns_hash)
          end

          # Convert child plan hashes recursively
          hash[:children_plans]&.each do |name, child_hash|
            plan.children_plans[name] = DeclarationPlan.from_hash(child_hash)
          end

          # Copy type namespaces directly
          hash[:type_namespaces]&.each do |attr_name, ns_class|
            plan.type_namespaces[attr_name] = ns_class
          end

          # Copy element strategies directly
          hash[:element_strategies]&.each do |attr_name, strategy|
            plan.element_strategies[attr_name] = strategy
          end

          plan
        end

        # Create an empty plan
        #
        # @return [DeclarationPlan] Empty plan instance
        def self.empty
          new
        end
      end
    end
  end
end