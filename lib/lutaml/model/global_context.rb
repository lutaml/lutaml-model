# frozen_string_literal: true

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
    # - Manages format-specific registries (e.g., XML namespace registry)
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

      # @return [Symbol] The current default context ID
      attr_reader :default_context_id

      # @return [Hash{String => Symbol}] Namespace URI to register ID mapping
      attr_reader :namespace_register_map

      # @return [Hash{Symbol => Object}] Format-specific registries
      attr_reader :format_registries

      # Thread-local storage for context switching
      THREAD_CONTEXT_KEY = :lutaml_model_context

      # Initialize the GlobalContext with default components.
      def initialize
        @registry = ContextRegistry.new
        @resolver = CachedTypeResolver.new(delegate: TypeResolver)
        @imports = ImportRegistry.new
        @format_registries = {}
        @default_context_id = :default
        @namespace_register_map = {} # namespace_uri => register_id
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
      # - All format-specific registries
      # - All namespace-register mappings
      #
      # @return [void]
      def reset!
        @mutex.synchronize do
          @registry.clear
          @resolver.clear_all_caches
          @imports.reset!
          @format_registries.each_value do |reg|
            reg.clear! if reg.respond_to?(:clear!)
          end
          @namespace_register_map.clear
          @default_context_id = :default
        end
      end

      # Clear caches only (keep registrations).
      #
      # @return [void]
      def clear_caches
        @resolver.clear_all_caches
        Register.clear_resolve_cache
      end

      # =====================================================================
      # Generic Format Registry Methods
      # =====================================================================

      # Register a format-specific registry.
      # Format plugins call this at load time to register their registries.
      #
      # @param format [Symbol] The format (e.g., :xml)
      # @param registry [Object] The registry instance (must respond to #clear!)
      # @return [void]
      def register_format_registry(format, registry)
        @mutex.synchronize do
          @format_registries[format] = registry
        end
      end

      # Get a format-specific registry.
      #
      # @param format [Symbol] The format
      # @return [Object, nil] The registry or nil if not registered
      def format_registry_for(format)
        @format_registries[format]
      end

      # Clear a specific format registry.
      #
      # @param format [Symbol] The format
      # @return [void]
      def clear_format_registry!(format)
        reg = @format_registries[format]
        reg&.clear! if reg.respond_to?(:clear!)
      end

      # Backward-compatible accessor for XML namespace registry.
      # Delegates to the generic format_registries hash.
      #
      # @return [Object, nil] The XML namespace class registry
      def xml_namespace_registry
        @format_registries[:xml]
      end

      # Backward-compatible clear for XML namespace registry.
      #
      # @return [void]
      def clear_xml_namespace_registry!
        clear_format_registry!(:xml)
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
          format_registries: @format_registries.keys,
          namespace_register_map_size: @namespace_register_map.size,
        }
      end

      # =====================================================================
      # Namespace-Register Mapping Methods
      # =====================================================================

      # @api public
      # Bind a register to a namespace URI.
      #
      # This enables reverse lookup: given a namespace URI, find the register.
      #
      # @param register_id [Symbol] The register ID
      # @param namespace_uri [String] The namespace URI
      # @return [void]
      def bind_register_to_namespace(register_id, namespace_uri)
        @mutex.synchronize do
          @namespace_register_map[namespace_uri] = register_id.to_sym
        end
      end

      # @api public
      # Get register ID for a namespace URI.
      #
      # @param namespace_uri [String] The namespace URI
      # @return [Symbol, nil] The register ID or nil if not bound
      def register_id_for_namespace(namespace_uri)
        @namespace_register_map[namespace_uri]
      end

      # @api public
      # Get register for a namespace URI.
      #
      # @param namespace_uri [String] The namespace URI
      # @return [Register, nil] The register or nil if not bound
      def register_for_namespace(namespace_uri)
        register_id = @namespace_register_map[namespace_uri]
        return nil unless register_id

        GlobalRegister.lookup(register_id)
      end

      # @api public
      # Resolve type using namespace-aware lookup.
      #
      # If a namespace is specified and a register is bound to that namespace,
      # uses that register for type resolution. Falls back to standard resolution.
      #
      # @param type_name [Symbol, String] The type name
      # @param namespace_uri [String, nil] The namespace URI (optional)
      # @param context_id [Symbol, nil] Optional explicit context
      # @return [Class, nil] The resolved type or nil
      def resolve_type_with_namespace(type_name, namespace_uri = nil,
context_id = nil)
        # If namespace specified, try namespace-aware resolution
        if namespace_uri
          register = register_for_namespace(namespace_uri)
          if register
            result = register.resolve_in_namespace(type_name, namespace_uri)
            return result if result
          end
        end

        # Fallback to standard resolution
        resolve_type(type_name, context_id)
      end

      class << self
        # Performance: Define delegation methods without closures
        # Using class_eval with string avoids closure allocation per call

        class_eval <<-RUBY, __FILE__, __LINE__ + 1
          def registry
            instance.registry
          end

          def resolver
            instance.resolver
          end

          def imports
            instance.imports
          end

          def format_registries
            instance.format_registries
          end

          def xml_namespace_registry
            instance.xml_namespace_registry
          end

          def default_context_id
            instance.default_context_id
          end

          def default_context
            instance.default_context
          end

          def context(*args, **kwargs, &block)
            instance.context(*args, **kwargs, &block)
          end

          def clear_xml_namespace_registry!
            instance.clear_xml_namespace_registry!
          end

          def reset!
            instance.reset!
          end

          def clear_caches
            instance.clear_caches
          end

          def stats
            instance.stats
          end

          def default_context_id=(id)
            instance.default_context_id = id
          end

          def register_context(ctx)
            instance.register_context(ctx)
          end

          def unregister_context(id)
            instance.unregister_context(id)
          end

          def create_context(**kwargs)
            instance.create_context(**kwargs)
          end

          def context_ids
            instance.instance_variable_get(:@registry).context_ids
          end

          def resolve_type(name, ctx = nil)
            instance.resolve_type(name, ctx)
          end

          def resolvable?(name, ctx = nil)
            instance.resolvable?(name, ctx)
          end

          def with_context(ctx_id)
            instance.with_context(ctx_id) { yield }
          end

          def register_format_registry(format, registry)
            instance.register_format_registry(format, registry)
          end

          def format_registry_for(format)
            instance.format_registry_for(format)
          end

          def clear_format_registry!(format)
            instance.clear_format_registry!(format)
          end

          # Namespace-register mapping methods
          def bind_register_to_namespace(register_id, namespace_uri)
            instance.bind_register_to_namespace(register_id, namespace_uri)
          end

          def register_id_for_namespace(namespace_uri)
            instance.register_id_for_namespace(namespace_uri)
          end

          def register_for_namespace(namespace_uri)
            instance.register_for_namespace(namespace_uri)
          end

          def resolve_type_with_namespace(type_name, namespace_uri = nil, context_id = nil)
            instance.resolve_type_with_namespace(type_name, namespace_uri, context_id)
          end

          def namespace_register_map
            instance.namespace_register_map
          end
        RUBY
      end
    end
  end
end
