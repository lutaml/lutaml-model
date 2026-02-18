# frozen_string_literal: true

require "forwardable"

module Lutaml
  module Model
    # GlobalContext provides global state management and context coordination.
    #
    # Architecture Overview:
    # - Register: User-facing API for type registration (primary user interface)
    # - GlobalRegister: User-facing API for register management
    # - GlobalContext: Internal coordinator for context management
    #
    # Users typically interact with Register and GlobalRegister.
    # GlobalContext is used internally and for advanced use cases.
    #
    # This class:
    # - Manages named contexts via ContextRegistry
    # - Provides type resolution via CachedTypeResolver
    # - Manages imports via ImportRegistry
    # - Manages XML namespace registry
    # - Provides `reset!` for test isolation
    # - Provides `with_context` for scoped operations
    #
    # @example Test isolation
    #   GlobalContext.reset!  # Clears ALL caches and non-default contexts
    #
    # @example Thread-safe context switching
    #   GlobalContext.with_context(:my_app) do
    #     # Code here uses :my_app as default context
    #   end
    #
    # @see Register For type registration (primary user interface)
    # @see GlobalRegister For register management (primary user interface)
    #
    class GlobalContext
      include Singleton

      # @return [ContextRegistry] The context registry
      attr_reader :registry

      # @return [CachedTypeResolver] The cached type resolver
      attr_reader :resolver

      # @return [ImportRegistry] The import registry
      attr_reader :imports

      # @return [Xml::NamespaceClassRegistry] The XML namespace class registry
      attr_reader :xml_namespace_registry

      # @return [Symbol] The current default context ID
      attr_reader :default_context_id

      # Thread-local storage for context switching
      THREAD_CONTEXT_KEY = :lutaml_model_context

      # Initialize the GlobalContext with default components.
      def initialize
        @registry = ContextRegistry.new
        @resolver = CachedTypeResolver.new(delegate: TypeResolver)
        @imports = ImportRegistry.new
        @xml_namespace_registry = create_xml_namespace_registry
        @default_context_id = :default
        @mutex = Mutex.new
      end

      # Get the current default context.
      #
      # @return [TypeContext] The current default context
      def default_context
        context_id = Thread.current[THREAD_CONTEXT_KEY] || @default_context_id
        @registry.lookup(context_id) || @registry.lookup(:default)
      end

      # Set the default context ID.
      #
      # @param id [Symbol] The new default context ID
      # @return [void]
      def default_context_id=(id)
        @mutex.synchronize do
          @default_context_id = id.to_sym
        end
      end

      # Get a context by ID, or the default if no ID provided.
      #
      # @param id [Symbol, nil] The context ID (optional)
      # @return [TypeContext] The context
      def context(id = nil)
        if id
          @registry.lookup(id.to_sym)
        else
          default_context
        end
      end

      # Resolve a type name to a class using the default context.
      #
      # @param name [Symbol, String, Class] The type name or class
      # @param context_id [Symbol, nil] Optional context ID (uses default if not provided)
      # @return [Class] The resolved type class
      # @raise [UnknownTypeError] If type cannot be resolved
      def resolve_type(name, context_id = nil)
        ctx = context(context_id)
        @resolver.resolve(name, ctx)
      end

      # Check if a type is resolvable.
      #
      # @param name [Symbol, String, Class] The type name or class
      # @param context_id [Symbol, nil] Optional context ID
      # @return [Boolean] true if resolvable
      def resolvable?(name, context_id = nil)
        ctx = context(context_id)
        @resolver.resolvable?(name, ctx)
      end

      # Register a context.
      #
      # @param context [TypeContext] The context to register
      # @return [void]
      def register_context(context)
        @registry.register(context)
      end

      # Create and register a new context.
      #
      # @param id [Symbol] The context ID
      # @param registry [TypeRegistry, nil] Optional type registry
      # @param fallback_to [Array<Symbol, TypeContext>] Fallback contexts
      # @param substitutions [Array<TypeSubstitution, Hash>] Type substitutions
      # @return [TypeContext] The created context
      def create_context(id:, registry: nil, fallback_to: [], substitutions: [])
        @registry.create(
          id: id,
          registry: registry,
          fallback_to: fallback_to,
          substitutions: substitutions,
        )
      end

      # Unregister a context and clear its caches.
      #
      # @param id [Symbol] The context ID
      # @return [TypeContext, nil] The removed context or nil
      def unregister_context(id)
        @resolver.clear_cache(id)
        @registry.unregister(id)
      end

      # Execute a block with a specific context as default.
      #
      # @param context_id [Symbol] The context ID to use
      # @yield Block to execute with the context
      # @return [Object] The block's return value
      def with_context(context_id)
        previous = Thread.current[THREAD_CONTEXT_KEY]
        Thread.current[THREAD_CONTEXT_KEY] = context_id.to_sym
        begin
          yield
        ensure
          Thread.current[THREAD_CONTEXT_KEY] = previous
        end
      end

      # Reset ALL global state (for testing).
      #
      # This clears:
      # - All non-default contexts
      # - All type resolution caches
      # - All pending imports
      # - All XML namespace class registry entries
      #
      # @return [void]
      def reset!
        @mutex.synchronize do
          @registry.clear
          @resolver.clear_all_caches
          @imports.reset!
          @xml_namespace_registry&.clear!
          @xml_namespace_registry = create_xml_namespace_registry
          @default_context_id = :default
        end
      end

      # Clear caches only (keep registrations).
      #
      # @return [void]
      def clear_caches
        @resolver.clear_all_caches
      end

      # Clear XML namespace registry (for testing).
      #
      # @return [void]
      def clear_xml_namespace_registry!
        @xml_namespace_registry&.clear!
      end

      # Get statistics about the global context.
      #
      # @return [Hash] Statistics including registry, resolver, and imports
      def stats
        {
          contexts: @registry.context_ids,
          default_context_id: @default_context_id,
          resolver_cache_size: @resolver.cache_stats[:size],
          imports: @imports.stats,
          xml_namespace_registry: "managed",
        }
      end

      private

      # Create a new XML namespace class registry.
      #
      # Lazy load to avoid circular dependencies.
      #
      # @return [Xml::NamespaceClassRegistry] The registry
      def create_xml_namespace_registry
        require_relative "xml/namespace_class_registry"
        Xml::NamespaceClassRegistry.new
      end

      class << self
        extend Forwardable

        # Delegate instance methods to the singleton instance.
        #
        # This allows calling GlobalContext.resolve_type instead of
        # GlobalContext.instance.resolve_type

        def_delegators :instance, :registry, :resolver, :imports,
                       :xml_namespace_registry, :clear_xml_namespace_registry!,
                       :default_context_id, :default_context_id=,
                       :default_context, :context, :resolve_type, :resolvable?,
                       :register_context, :create_context, :unregister_context,
                       :with_context, :reset!, :clear_caches, :stats
      end
    end
  end
end
