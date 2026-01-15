# frozen_string_literal: true

module Lutaml
  module Model
    module KeyValueDataModel
      # Represents a key-value element for JSON, YAML, TOML formats.
      #
      # This class provides an intermediate representation for key-value
      # data structures, separating content (what to serialize) from
      # presentation (how to serialize).
      #
      # Unlike Hash, KeyValueElement is an explicit OOP model that can:
      # - Track metadata about value types
      # - Support transformation logic
      # - Maintain clear separation of concerns
      # - Enable format-specific optimizations
      #
      # @example Simple key-value
      #   element = KeyValueElement.new("name", "John")
      #   element.to_hash
      #   # => {"name" => "John"}
      #
      # @example Nested structure
      #   parent = KeyValueElement.new("person")
      #   parent.add_child(KeyValueElement.new("name", "John"))
      #   parent.add_child(KeyValueElement.new("age", 30))
      #   parent.to_hash
      #   # => {"person" => {"name" => "John", "age" => 30}}
      #
      # @example Array values
      #   element = KeyValueElement.new("items")
      #   element.add_child("apple")
      #   element.add_child("banana")
      #   element.to_hash
      #   # => {"items" => ["apple", "banana"]}
      class KeyValueElement
        # @return [String] Key name
        attr_reader :key

        # @return [Object, nil] Direct value (for leaf nodes)
        attr_accessor :value

        # @return [Array<KeyValueElement, Object>] Child elements
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
        # @param child [KeyValueElement, Object] Child to add
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

        # Convert to Hash representation
        #
        # This is the primary method for adapter rendering.
        # The conversion logic follows these rules:
        # 1. If has direct value and no children: {key => value}
        # 2. If has children that are all KeyValueElements: {key => merged_hash}
        # 3. If has children that are mixed/primitives: {key => array}
        # 4. If has both value and children: children take precedence
        # 5. Special case: __root__ with no children returns empty hash (for omitted attributes)
        #
        # @return [Hash]
        def to_hash
          if has_children?
            { @key => children_to_value }
          elsif has_value?
            { @key => @value }
          else
            # Special case: __root__ element should return empty hash when all attributes omitted
            # This allows hash["__root__"].keys to work without raising NoMethodError
            { @key => (@key == "__root__" ? {} : nil) }
          end
        end

        # String representation for debugging
        #
        # @return [String]
        def to_s
          if leaf?
            "<KeyValueElement key=#{@key.inspect} value=#{@value.inspect}>"
          elsif has_children?
            "<KeyValueElement key=#{@key.inspect} children=#{@children.length}>"
          else
            "<KeyValueElement key=#{@key.inspect}>"
          end
        end

        # Hash-like access for backward compatibility
        #
        # Allows KeyValueElement to be used like a hash in tests and existing code.
        # Converts to hash first, then accesses the key.
        #
        # @param key [String, Symbol] Key to access
        # @return [Object] Value for the key
        def [](key)
          hash = to_hash
          # If this is the root element, access the inner hash
          if @key == "__root__" && hash.key?("__root__")
            inner = hash["__root__"]
            inner.is_a?(Hash) ? inner[key.to_s] : nil
          else
            hash[key.to_s]
          end
        end

        # Hash-like assignment for backward compatibility
        #
        # Allows KeyValueElement to be used like a hash in tests and existing code.
        # Creates a new child KeyValueElement for the key-value pair.
        #
        # @param key [String, Symbol] Key to set
        # @param value [Object] Value to set
        # @return [Object] The assigned value
        def []=(key, value)
          # For root element, add child with the key-value pair
          if @key == "__root__"
            # Remove existing child with same key if any
            @children.reject! do |child|
              child.is_a?(KeyValueElement) && child.key == key.to_s
            end
            # Add new child
            @children << KeyValueElement.new(key.to_s, value)
          else
            # For non-root elements, convert to hash and merge
            # This shouldn't normally happen in the transformation flow
            @children << KeyValueElement.new(key.to_s, value)
          end
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
            # Mixed: some KeyValueElements, some primitives
            # Convert all to their values and return as array
            @children.map do |child|
              child.is_a?(KeyValueElement) ? child.to_hash.values.first : child
            end
          end
        end

        # Convert children to merged Hash
        #
        # @return [Hash]
        def children_to_hash
          @children.map(&:to_hash).reduce({}, :merge)
        end

        # Convert children to Array
        #
        # @return [Array]
        def children_to_array
          @children
        end

        # Check if all children are KeyValueElements
        #
        # @return [Boolean]
        def all_key_value_elements?
          @children.all? { |c| c.is_a?(KeyValueElement) }
        end

        # Check if all children are primitives (not KeyValueElements)
        #
        # @return [Boolean]
        def all_primitives?
          @children.none? { |c| c.is_a?(KeyValueElement) }
        end
      end
    end
  end
end