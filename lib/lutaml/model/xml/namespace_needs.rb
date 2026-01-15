# frozen_string_literal: true

require "set"
require_relative "type_namespace/reference"

module Lutaml
  module Model
    module Xml
      # Collects namespace usage data during collection phase
      # Replaces schema-less needs hash with proper OOP structure
      #
      # This class maintains MECE responsibility: it only stores and organizes
      # namespace needs data. It does NOT make decisions or build XML.
      class NamespaceNeeds
        attr_reader :namespaces, :children, :type_namespaces,
                    :type_namespace_classes, :type_attribute_namespaces,
                    :type_element_namespaces, :type_refs,
                    :namespace_scope_configs

        def initialize
          @namespaces = {}  # Hash<String, NamespaceUsage>
          @children = {}    # Hash<Symbol, NamespaceNeeds>
          @type_namespaces = {}  # Hash<Symbol, Class>
          @type_namespace_classes = Set.new  # Set<Class>
          @type_attribute_namespaces = Set.new  # Set<Class>
          @type_element_namespaces = Set.new  # Set<Class>
          @type_refs = []  # Array<TypeNamespace::Reference>
          @namespace_scope_configs = []  # Array<NamespaceScopeConfig>
        end

        # Add namespace usage for a specific namespace
        # @param key [String] Namespace key (from namespace_class.to_key)
        # @param usage [NamespaceUsage] Usage information
        def add_namespace(key, usage)
          unless usage.is_a?(NamespaceUsage)
            raise ArgumentError, "Expected NamespaceUsage, got #{usage.class}"
          end
          @namespaces[key] = usage
        end

        # Track a type namespace for a specific attribute
        # @param attr_name [Symbol] Attribute name
        # @param ns_class [Class] XmlNamespace class
        def add_type_namespace(attr_name, ns_class)
          @type_namespaces[attr_name] = ns_class
          @type_namespace_classes << ns_class
        end

        # Add type attribute namespace to tracking set
        # @param ns_class [Class] XmlNamespace class
        def add_type_attribute_namespace(ns_class)
          @type_attribute_namespaces << ns_class
          @type_namespace_classes << ns_class
        end

        # Add type element namespace to tracking set
        # @param ns_class [Class] XmlNamespace class
        def add_type_element_namespace(ns_class)
          @type_element_namespaces << ns_class
          @type_namespace_classes << ns_class
        end

        # Add a type reference for lazy resolution
        # @param reference [TypeNamespace::Reference] Reference object
        def add_type_ref(reference)
          unless reference.is_a?(TypeNamespace::Reference)
            raise ArgumentError, "Expected TypeNamespace::Reference, got #{reference.class}"
          end
          @type_refs << reference
        end

        # Clear type references after resolution
        # Used by TypeNamespaceResolver to prevent reprocessing
        def clear_type_refs
          @type_refs.clear
        end

        # Add namespace scope configuration
        # @param config [NamespaceScopeConfig] Configuration object
        def add_namespace_scope_config(config)
          unless config.is_a?(NamespaceScopeConfig)
            raise ArgumentError, "Expected NamespaceScopeConfig, got #{config.class}"
          end
          @namespace_scope_configs << config
        end

        # Add child needs
        # @param name [Symbol] Child attribute name
        # @param child_needs [NamespaceNeeds] Child's namespace needs
        def add_child(name, child_needs)
          unless child_needs.is_a?(NamespaceNeeds)
            raise ArgumentError, "Expected NamespaceNeeds, got #{child_needs.class}"
          end
          @children[name] = child_needs
        end

        # Merge another NamespaceNeeds into this one
        # @param other [NamespaceNeeds] Other needs to merge
        # @return [self]
        def merge(other)
          unless other.is_a?(NamespaceNeeds)
            raise ArgumentError, "Expected NamespaceNeeds, got #{other.class}"
          end

          # Merge namespaces
          other.namespaces.each do |key, usage|
            if @namespaces.key?(key)
              @namespaces[key].merge(usage)
            else
              @namespaces[key] = usage
            end
          end

          # Merge children
          other.children.each do |name, child_needs|
            if @children.key?(name)
              @children[name].merge(child_needs)
            else
              @children[name] = child_needs
            end
          end

          # Merge type namespaces
          @type_namespaces.merge!(other.type_namespaces)
          @type_namespace_classes.merge(other.type_namespace_classes)
          @type_attribute_namespaces.merge(other.type_attribute_namespaces)
          @type_element_namespaces.merge(other.type_element_namespaces)

          # Merge type refs
          @type_refs.concat(other.type_refs)

          # Merge namespace scope configs (avoiding duplicates)
          other.namespace_scope_configs.each do |config|
            unless @namespace_scope_configs.any? { |c| c.namespace_class == config.namespace_class }
              @namespace_scope_configs << config
            end
          end

          self
        end

        # Check if needs are empty
        # @return [Boolean]
        def empty?
          @namespaces.empty? &&
            @children.empty? &&
            @type_refs.empty? &&
            @type_namespaces.empty? &&
            @namespace_scope_configs.empty?
        end

        # Get namespace usage by key
        # @param key [String] Namespace key
        # @return [NamespaceUsage, nil]
        def namespace(key)
          @namespaces[key]
        end

        # Get child needs by name
        # @param name [Symbol] Child attribute name
        # @return [NamespaceNeeds, nil]
        def child(name)
          @children[name]
        end

        # Check if a namespace is in scope configuration
        # @param ns_class [Class] XmlNamespace class
        # @return [NamespaceScopeConfig, nil]
        def scope_config_for(ns_class)
          @namespace_scope_configs.find { |config| config.namespace_class == ns_class }
        end

        # Get all namespace classes (from usage and type namespaces)
        # @return [Set<Class>]
        def all_namespace_classes
          namespace_classes = Set.new(@namespaces.values.map(&:namespace_class))
          namespace_classes.merge(@type_namespace_classes)
        end

        # Validate internal consistency
        # @raise [RuntimeError] if inconsistent state detected
        def validate!
          # Type attribute and element namespaces should be mutually exclusive
          overlap = @type_attribute_namespaces & @type_element_namespaces
          unless overlap.empty?
            raise "Type namespaces appear in both attribute and element contexts: #{overlap.to_a}"
          end

          # All type namespace classes should be in type_namespace_classes
          @type_attribute_namespaces.each do |ns_class|
            unless @type_namespace_classes.include?(ns_class)
              raise "Type attribute namespace #{ns_class} not in type_namespace_classes"
            end
          end

          @type_element_namespaces.each do |ns_class|
            unless @type_namespace_classes.include?(ns_class)
              raise "Type element namespace #{ns_class} not in type_namespace_classes"
            end
          end

          true
        end
      end
    end
  end
end