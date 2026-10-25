# frozen_string_literal: true

module Lutaml
  module KeyValue
    module DataModel
      # Represents a key-value element for JSON, YAML, TOML formats.
      #
      # This class provides an intermediate representation for key-value
      # data structures, separating content (what to serialize) from
      # presentation (how to serialize).
      #
      # Unlike Hash, Element is an explicit OOP model that can:
      # - Track metadata about value types
      # - Support transformation logic
      # - Maintain clear separation of concerns
      # - Enable format-specific optimizations
      #
      # @example Simple key-value
      #   element = Element.new("name", "John")
      #   element.to_hash
      #   # => {"name" => "John"}
      #
      # @example Nested structure
      #   parent = Element.new("person")
      #   parent.add_child(Element.new("name", "John"))
      #   parent.add_child(Element.new("age", 30))
      #   parent.to_hash
      #   # => {"person" => {"name" => "John", "age" => 30}}
      #
      # @example Array values
      #   element = Element.new("items")
      #   element.add_child("apple")
      #   element.add_child("banana")
      #   element.to_hash
      #   # => {"items" => ["apple", "banana"]}
      class Element
        # @return [String] Key name
        attr_reader :key

        # @return [Object, nil] Direct value (for leaf nodes)
        attr_accessor :value

        # @return [Array<Element, Object>] Child elements
        attr_reader :children

        # Initialize a new key-value element
        #
        # @param key [String, Symbol] The key name
        # @param value [Object, nil] Optional direct value
        def initialize(key, value = nil)
          @key = key.to_s
          @value = value
          @children = []
        end

        # Add a child element or value
        #
        # This supports building nested structures and arrays.
        #
        # @param child [Element, Object] Child to add
        # @return [self]
        def add_child(child)
          @children << child
          self
        end

        # Check if element has children
        #
        # @return [Boolean]
        def has_children?
          !@children.empty?
        end

        # Check if element has a direct value
        #
        # @return [Boolean]
        def has_value?
          !@value.nil?
        end

        # Check if this is a leaf node (has value, no children)
        #
        # @return [Boolean]
        def leaf?
          has_value? && !has_children?
        end

        # The content this element carries, independent of its own key:
        # the child-merged structure when children exist, otherwise the
        # direct value (nil when neither). This is the half of to_hash
        # that survives the {key => ...} envelope, so callers that
        # assemble documents themselves never round-trip through a key.
        #
        # @return [Object, nil]
        def payload
          if has_children?
            children_to_value
          elsif has_value?
            @value
          end
        end

        # Convert to Hash representation
        #
        # This is the primary method for adapter rendering.
        # The conversion logic follows these rules:
        # 1. If has direct value and no children: {key => value}
        # 2. If has children that are all Elements: {key => merged_hash}
        # 3. If has children that are mixed/primitives: {key => array}
        # 4. If has both value and children: children take precedence
        #
        # @return [Hash]
        def to_hash
          { @key => payload }
        end

        # String representation for debugging
        #
        # @return [String]
        def to_s
          if leaf?
            "<Element key=#{@key.inspect} value=#{@value.inspect}>"
          elsif has_children?
            "<Element key=#{@key.inspect} children=#{@children.length}>"
          else
            "<Element key=#{@key.inspect}>"
          end
        end

        # Hash-like access for backward compatibility
        #
        # A child element's payload answers by the child's key; a leaf
        # answers by its own key ({"name" => "John"}["name"]). This is
        # what lets custom `to:` handlers build nested structures in
        # place: `doc["locality"] = {}; doc["locality"]["type"] = v` —
        # the read returns the child's value hash and the write mutates
        # it in place.
        #
        # @param key [String, Symbol] Key to access
        # @return [Object] Value for the key
        def [](key)
          key = key.to_s
          child = @children.find { |c| c.is_a?(Element) && c.key == key }
          child ? child.payload : to_hash[key]
        end

        # Hash-like assignment for backward compatibility
        #
        # Allows Element to be used like a hash in tests and existing code.
        # Replaces any existing child element of the same key, then adds
        # a new child Element for the key-value pair.
        #
        # @param key [String, Symbol] Key to set
        # @param value [Object] Value to set
        # @return [Object] The assigned value
        def []=(key, value)
          key = key.to_s
          @children.reject! do |child|
            child.is_a?(Element) && child.key == key
          end
          @children << Element.new(key, value)
          value
        end

        # Detailed inspection for debugging
        #
        # @return [String]
        def inspect
          to_s
        end

        private

        # Convert children to appropriate value representation
        #
        # @return [Hash, Array, Object]
        def children_to_value
          if all_key_value_elements?
            children_to_hash
          elsif all_primitives?
            children_to_array
          else
            # Mixed: some Elements, some primitives
            # Convert all to their values and return as array
            @children.map do |child|
              child.is_a?(Element) ? child.to_hash.values.first : child
            end
          end
        end

        # Convert children to merged Hash
        #
        # @return [Hash]
        def children_to_hash
          # Built in place: map+reduce(:merge) allocated the mapped
          # array plus one merged hash per reduce step (TODO.perf 16).
          h = {}
          @children.each { |child| h.update(child.to_hash) }
          h
        end

        # Convert children to Array
        #
        # @return [Array]
        def children_to_array
          @children
        end

        # Check if all children are Elements
        #
        # @return [Boolean]
        def all_key_value_elements?
          @children.all?(Element)
        end

        # Check if all children are primitives (not Elements)
        #
        # @return [Boolean]
        def all_primitives?
          @children.none?(Element)
        end
      end
    end
  end
end
