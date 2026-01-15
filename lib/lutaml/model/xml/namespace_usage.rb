# frozen_string_literal: true

require "set"

module Lutaml
  module Model
    module Xml
      # Tracks how a namespace is used (elements, attributes, etc.)
      # Replaces {ns_object:, used_in:, children_use:, children_need_prefix:} hash
      #
      # This class maintains MECE responsibility: it only tracks namespace usage.
      # It does NOT make decisions about format or location.
      class NamespaceUsage
        attr_reader :namespace_class, :used_in, :children_use
        attr_accessor :children_need_prefix

        # Initialize namespace usage tracking
        # @param namespace_class [Class] XmlNamespace class
        def initialize(namespace_class)
          @namespace_class = namespace_class
          @used_in = Set.new  # Set of contexts: :elements, :attributes, :content
          @children_use = Set.new  # Set of child attribute names
          @children_need_prefix = false
        end

        # Mark namespace as used in a specific context
        # @param context [Symbol] Context: :elements, :attributes, or :content
        def mark_used_in(context)
          unless [:elements, :attributes, :content].include?(context)
            raise ArgumentError, "Invalid context: #{context}. Must be :elements, :attributes, or :content"
          end
          @used_in << context
        end

        # Mark namespace as used by a child
        # @param child_name [Symbol] Child attribute name
        def mark_child_use(child_name)
          @children_use << child_name
        end

        # Check if namespace is used in elements
        # @return [Boolean]
        def used_in_elements?
          @used_in.include?(:elements)
        end

        # Check if namespace is used in attributes
        # @return [Boolean]
        def used_in_attributes?
          @used_in.include?(:attributes)
        end

        # Check if namespace is used in content
        # @return [Boolean]
        def used_in_content?
          @used_in.include?(:content)
        end

        # Check if namespace is used by any children
        # @return [Boolean]
        def used_by_children?
          !@children_use.empty?
        end

        # Merge another usage into this one
        # @param other [NamespaceUsage] Other usage to merge
        # @return [self]
        def merge(other)
          unless other.is_a?(NamespaceUsage)
            raise ArgumentError, "Expected NamespaceUsage, got #{other.class}"
          end

          unless other.namespace_class == @namespace_class
            raise ArgumentError, "Cannot merge usage for different namespaces: #{@namespace_class} != #{other.namespace_class}"
          end

          @used_in.merge(other.used_in)
          @children_use.merge(other.children_use)
          @children_need_prefix ||= other.children_need_prefix

          self
        end

        # Get namespace key for lookups
        # @return [String]
        def key
          @namespace_class.to_key
        end

        # Check if empty (no usage tracked)
        # @return [Boolean]
        def empty?
          @used_in.empty? && @children_use.empty?
        end

        # Backward compatibility: allow hash-style access
        # Maps old hash keys to new OOP attributes
        # @param key [Symbol] Accessor key
        # @return [Object] Corresponding attribute value
        def [](key)
          case key
          when :ns_object, :namespace_class then @namespace_class
          when :used_in then @used_in
          when :children_use then @children_use
          when :children_need_prefix then @children_need_prefix
          else
            raise KeyError, "Unknown key: #{key.inspect}"
          end
        end

        # String representation for debugging
        # @return [String]
        def inspect
          "#<NamespaceUsage #{@namespace_class} used_in=#{@used_in.to_a} children=#{@children_use.to_a}>"
        end
      end
    end
  end
end