# frozen_string_literal: true

module Lutaml
  module Model
    # ContextRegistry stores and retrieves named TypeContext instances.
    #
    # This is an INTERNAL class. Users should use Register and GlobalRegister.
    #
    # Responsibility: Store and manage named TypeContext instances
    #
    # This class:
    # - Simple key-value store (Symbol => TypeContext)
    # - NOT a singleton - can have multiple registries
    # - Thread-safe with Mutex protection
    # - Always contains :default context after initialization
    #
    # @api private
    #
    # @example Basic usage
    #   registry = ContextRegistry.new
    #   registry.register(my_context)
    #   registry.lookup(:my_context)  #=> my_context
    #
    # @example Creating and registering a context
    #   registry = ContextRegistry.new
    #   registry.create(id: :my_app, fallback_to: [:default])
    #   registry.lookup(:my_app)  #=> TypeContext with id :my_app
    #
    class ContextRegistry
      # @return [Hash<Symbol, TypeContext>] The registered contexts
      attr_reader :contexts

      # Create a new ContextRegistry.
      # Automatically registers the :default context.
      def initialize
        @contexts = {}
        @mutex = Mutex.new
        # Always register the default context
        register(TypeContext.default)
      end

      # Register a context.
      #
      # @param context [TypeContext] The context to register
      # @return [void]
      # @raise [ArgumentError] If context is not a TypeContext
      def register(context)
        unless context.is_a?(TypeContext)
          raise ArgumentError, "Expected TypeContext, got #{context.class}"
        end

        @mutex.synchronize do
          @contexts[context.id] = context
        end
      end

      # Look up a context by ID.
      #
      # @param id [Symbol, String] The context ID
      # @return [TypeContext, nil] The context or nil if not found
      def lookup(id)
        @mutex.synchronize do
          @contexts[id.to_sym]
        end
      end

      # Remove a context by ID.
      #
      # @param id [Symbol, String] The context ID
      # @return [TypeContext, nil] The removed context or nil if not found
      def unregister(id)
        @mutex.synchronize do
          @contexts.delete(id.to_sym)
        end
      end

      # Check if a context exists.
      #
      # @param id [Symbol, String] The context ID
      # @return [Boolean] true if context exists
      def exists?(id)
        @mutex.synchronize do
          @contexts.key?(id.to_sym)
        end
      end

      # Get all registered context IDs.
      #
      # @return [Array<Symbol>] The context IDs
      def context_ids
        @mutex.synchronize do
          @contexts.keys
        end
      end

      # Get the number of registered contexts.
      #
      # @return [Integer] The number of contexts
      def size
        @mutex.synchronize do
          @contexts.size
        end
      end

      # Check if registry is empty (excluding default).
      #
      # @return [Boolean] true if only default context exists
      def empty?
        @mutex.synchronize do
          @contexts.size == 1 && @contexts.key?(:default)
        end
      end

      # Add a type substitution to an existing context.
      #
      # Since TypeContext is immutable, this creates a new context
      # with the substitution added and replaces the old one.
      #
      # @param context_id [Symbol] The context ID
      # @param from_type [Class] Type to substitute from
      # @param to_type [Class] Type to substitute to
      # @return [TypeContext, nil] The new context or nil if not found
      def register_substitution(context_id, from_type, to_type)
        @mutex.synchronize do
          context = @contexts[context_id.to_sym]
          return nil unless context

          new_context = context.add_substitution(from_type: from_type,
                                                 to_type: to_type)
          @contexts[context_id.to_sym] = new_context
          new_context
        end
      end

      # Create and register a new derived context.
      #
      # @param id [Symbol] The context ID
      # @param registry [TypeRegistry] Optional type registry (new one created if not provided)
      # @param fallback_to [Array<Symbol, TypeContext>] Fallback contexts
      # @param substitutions [Array<TypeSubstitution, Hash>] Type substitutions
      # @return [TypeContext] The created context
      def create(id:, registry: nil, fallback_to: [], substitutions: [])
        # Resolve fallback symbols to contexts
        resolved_fallbacks = Array(fallback_to).filter_map do |ctx|
          resolve_fallback(ctx)
        end

        # Create new registry if not provided
        type_registry = registry || TypeRegistry.new

        context = TypeContext.derived(
          id: id,
          registry: type_registry,
          fallback_to: resolved_fallbacks,
          substitutions: substitutions,
        )

        register(context)
        context
      end

      # Clear all contexts except default.
      #
      # @return [void]
      def clear
        @mutex.synchronize do
          @contexts.clear
          @contexts[:default] = TypeContext.default
        end
      end

      # Iterate over all contexts.
      #
      # @yield [Symbol, TypeContext] Yields id and context
      # @return [Enumerator] If no block given
      def each(&block)
        @mutex.synchronize do
          @contexts.each(&block)
        end
      end

      # Iterate over all context IDs.
      #
      # @yield [Symbol] Yields context id
      # @return [Enumerator] If no block given
      def each_key(&block)
        @mutex.synchronize do
          @contexts.each_key(&block)
        end
      end

      private

      # Resolve a fallback reference to a TypeContext.
      #
      # @param ctx [Symbol, TypeContext] The fallback reference
      # @return [TypeContext, nil] The resolved context or nil
      def resolve_fallback(ctx)
        case ctx
        when TypeContext
          ctx
        when Symbol, String
          lookup(ctx.to_sym)
        end
      end
    end
  end
end
