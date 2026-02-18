# frozen_string_literal: true

module Lutaml
  module Model
    # TypeRegistry is a pure data store for type mappings.
    #
    # This is an INTERNAL class. Users should use Register and GlobalRegister.
    #
    # Responsibility: Store and retrieve type mappings (Symbol => Class)
    #
    # This class has NO knowledge of:
    # - Type resolution logic (see TypeResolver)
    # - Type substitution (see TypeSubstitution)
    # - Fallback chains (see TypeContext)
    # - Caching (see CachedTypeResolver)
    #
    # @api private
    #
    # @example Basic usage
    #   registry = TypeRegistry.new
    #   registry.register(:string, Lutaml::Model::Type::String)
    #   registry.lookup(:string) #=> Lutaml::Model::Type::String
    #   registry.registered?(:string) #=> true
    #
    # @example Iterating over registered types
    #   registry.names #=> [:string, :integer, :boolean]
    #
    class TypeRegistry
      # Initialize a new empty TypeRegistry
      def initialize
        @types = {}
      end

      # Register a type class with a given name
      #
      # @param name [Symbol, String] The name to register the type under
      # @param klass [Class] The type class to register
      # @return [Class] The registered class
      #
      # @example
      #   registry.register(:custom_text, MyCustomText)
      def register(name, klass)
        @types[name.to_sym] = klass
      end

      # Look up a type class by name
      #
      # @param name [Symbol, String] The name of the type to look up
      # @return [Class, nil] The type class, or nil if not found
      #
      # @example
      #   registry.lookup(:string) #=> Lutaml::Model::Type::String
      #   registry.lookup(:unknown) #=> nil
      def lookup(name)
        @types[name.to_sym]
      end

      # Check if a type is registered
      #
      # @param name [Symbol, String] The name of the type to check
      # @return [Boolean] true if the type is registered, false otherwise
      #
      # @example
      #   registry.registered?(:string) #=> true
      #   registry.registered?(:unknown) #=> false
      def registered?(name)
        @types.key?(name.to_sym)
      end

      # Get all registered type names
      #
      # @return [Array<Symbol>] List of all registered type names
      #
      # @example
      #   registry.names #=> [:string, :integer, :boolean]
      def names
        @types.keys
      end

      # Clear all registered types
      #
      # This is primarily useful for testing to ensure isolation.
      #
      # @return [Hash] Empty hash
      #
      # @example
      #   registry.clear #=> {}
      def clear
        @types.clear
      end

      # Check if the registry is empty
      #
      # @return [Boolean] true if no types are registered
      def empty?
        @types.empty?
      end

      # Get the number of registered types
      #
      # @return [Integer] Number of registered types
      def size
        @types.size
      end

      # Iterate over all registered types
      #
      # @yield [Symbol, Class] Yields name and class for each registered type
      # @return [Enumerator] If no block given
      #
      # @example
      #   registry.each { |name, klass| puts "#{name}: #{klass}" }
      def each(&block)
        @types.each(&block)
      end

      # Create a copy of this registry
      #
      # @return [TypeRegistry] A new registry with the same types
      def dup
        new_registry = self.class.new
        @types.each do |name, klass|
          new_registry.register(name, klass)
        end
        new_registry
      end

      # Merge another registry into this one
      #
      # @param other [TypeRegistry] Another registry to merge
      # @return [TypeRegistry] self for chaining
      def merge!(other)
        other.instance_variable_get(:@types).each do |name, klass|
          register(name, klass) unless registered?(name)
        end
        self
      end

      # Create a new registry by merging this one with another
      #
      # @param other [TypeRegistry] Another registry to merge
      # @return [TypeRegistry] A new merged registry
      def merge(other)
        dup.merge!(other)
      end
    end
  end
end
