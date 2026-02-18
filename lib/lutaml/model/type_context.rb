# frozen_string_literal: true

module Lutaml
  module Model
    # TypeContext bundles all information needed for type resolution.
    #
    # This is an INTERNAL class. Users should use Register and GlobalRegister.
    #
    # Responsibility: Encapsulate the resolution context (registry + substitutions + fallbacks)
    #
    # This class:
    # - Bundles all info needed for type resolution
    # - Provides factory methods for common patterns
    # - Used internally by Register and GlobalContext
    # - Does NOT perform resolution (delegates to TypeResolver)
    #
    # @api private
    #
    # @example Default context (built-in types only)
    #   context = TypeContext.default
    #   # Has built-in types (string, integer, boolean, etc.)
    #   # No fallbacks, no substitutions
    #
    # @example Isolated context (no fallbacks)
    #   registry = TypeRegistry.new
    #   registry.register(:custom, MyCustomClass)
    #   context = TypeContext.isolated(:my_app, registry)
    #   # Has only :custom type, no fallback to default
    #
    # @example Derived context (with fallbacks)
    #   registry = TypeRegistry.new
    #   registry.register(:custom, MyCustomClass)
    #   context = TypeContext.derived(
    #     id: :my_app,
    #     registry: registry,
    #     fallback_to: [:default]
    #   )
    #   # Has :custom, falls back to default for built-in types
    #
    class TypeContext
      # @return [Symbol] The context identifier
      attr_reader :id

      # @return [TypeRegistry] The primary type registry
      attr_reader :registry

      # @return [Array<TypeSubstitution>] Type substitution rules
      attr_reader :substitutions

      # @return [Array<TypeContext>] Fallback contexts (in order)
      attr_reader :fallback_contexts

      # Create a new TypeContext.
      #
      # @param id [Symbol] The context identifier
      # @param registry [TypeRegistry] The primary type registry
      # @param substitutions [Array<TypeSubstitution>] Type substitution rules
      # @param fallback_contexts [Array<TypeContext>] Fallback contexts
      def initialize(id:, registry:, substitutions: [], fallback_contexts: [])
        @id = id.to_sym
        @registry = registry
        @substitutions = Array(substitutions).freeze
        @fallback_contexts = Array(fallback_contexts).freeze
        freeze
      end

      # Factory: Create the default context with built-in types.
      #
      # The default context contains all built-in types (string, integer, etc.)
      # and has no fallbacks or substitutions.
      #
      # @return [TypeContext] The default context
      def self.default
        @default ||= begin
          registry = TypeRegistry.new
          register_builtin_types_in(registry)
          new(
            id: :default,
            registry: registry,
            substitutions: [],
            fallback_contexts: [],
          )
        end
      end

      # Factory: Create an isolated context with no fallbacks.
      #
      # An isolated context only has the types explicitly registered
      # in its registry. It does not fall back to any other context.
      #
      # @param id [Symbol] The context identifier
      # @param registry [TypeRegistry] The type registry
      # @return [TypeContext] An isolated context
      def self.isolated(id, registry)
        new(
          id: id,
          registry: registry,
          substitutions: [],
          fallback_contexts: [],
        )
      end

      # Factory: Create a derived context with fallbacks.
      #
      # A derived context has its own types but can fall back to
      # other contexts when a type is not found.
      #
      # @param id [Symbol] The context identifier
      # @param registry [TypeRegistry] The primary type registry
      # @param fallback_to [Array<Symbol, TypeContext>] Fallback context IDs or contexts
      # @param substitutions [Array<TypeSubstitution, Hash>] Substitution rules
      # @return [TypeContext] A derived context
      def self.derived(id:, registry:, fallback_to: [], substitutions: [])
        # Resolve fallback context IDs to actual contexts
        fallback_contexts = Array(fallback_to).filter_map do |ctx|
          resolve_fallback_context(ctx)
        end

        # Normalize substitutions
        sub_objects = Array(substitutions).map do |s|
          normalize_substitution(s)
        end

        new(
          id: id,
          registry: registry,
          substitutions: sub_objects,
          fallback_contexts: fallback_contexts,
        )
      end

      # Add a type substitution to this context.
      #
      # Note: This creates a new context since TypeContext is immutable.
      #
      # @param from_type [Class] Type to substitute from
      # @param to_type [Class] Type to substitute to
      # @return [TypeContext] New context with the substitution added
      def add_substitution(from_type:, to_type:)
        new_sub = TypeSubstitution.new(from_type: from_type, to_type: to_type)
        self.class.new(
          id: id,
          registry: registry,
          substitutions: substitutions + [new_sub],
          fallback_contexts: fallback_contexts,
        )
      end

      # Create a copy with different fallbacks.
      #
      # @param fallback_to [Array<Symbol, TypeContext>] New fallback contexts
      # @return [TypeContext] New context with updated fallbacks
      def with_fallbacks(fallback_to:)
        fallback_contexts = Array(fallback_to).filter_map do |ctx|
          self.class.resolve_fallback_context(ctx)
        end

        self.class.new(
          id: id,
          registry: registry,
          substitutions: substitutions,
          fallback_contexts: fallback_contexts,
        )
      end

      # Check if this context has any fallbacks.
      #
      # @return [Boolean] true if has fallbacks
      def has_fallbacks?
        !fallback_contexts.empty?
      end

      # Get all fallback context IDs.
      #
      # @return [Array<Symbol>] Fallback context IDs
      def fallback_ids
        fallback_contexts.map(&:id)
      end

      # Check if a type is directly in this context's registry.
      #
      # @param name [Symbol, String] Type name
      # @return [Boolean] true if type is registered
      def has_type?(name)
        registry.registered?(name)
      end

      # Look up a type in this context's registry only.
      #
      # @param name [Symbol, String] Type name
      # @return [Class, nil] Type class or nil
      def lookup_local(name)
        registry.lookup(name)
      end

      # Find substitutions for a given type.
      #
      # @param from_type [Class, Symbol, String] The type to find substitutions for
      # @return [Array<TypeSubstitution>] Matching substitutions
      def substitution_for(from_type)
        from_type_class = from_type.is_a?(Class) ? from_type : nil

        substitutions.select do |sub|
          sub.from_type == from_type ||
            sub.from_type == from_type_class ||
            (from_type_class && sub.from_type == from_type_class.to_s)
        end
      end

      # Human-readable representation.
      #
      # @return [String] String representation
      def to_s
        fallback_str = has_fallbacks? ? " fallbacks=#{fallback_ids}" : ""
        "#<#{self.class.name} id=#{id}#{fallback_str}>"
      end

      alias inspect to_s

      # Equality check.
      #
      # Two contexts are equal if they have the same id.
      #
      # @param other [Object] Object to compare
      # @return [Boolean] true if equal
      def ==(other)
        return false unless other.is_a?(TypeContext)

        id == other.id
      end

      alias eql? ==

      # Hash code.
      #
      # @return [Integer] Hash code
      def hash
        id.hash
      end

      # Register built-in types in a registry.
      #
      # @param registry [TypeRegistry] Registry to populate
      # @return [void]
      def self.register_builtin_types_in(registry)
        # Delegate to Type module's new method
        Type.register_builtin_types_in(registry)
      end

      # @api private
      def self.resolve_fallback_context(ctx)
        case ctx
        when TypeContext
          ctx
        when Symbol, String
          # Try to look up from GlobalContext if available
          if defined?(GlobalContext) && GlobalContext.respond_to?(:registry)
            GlobalContext.registry.lookup(ctx)
          end
        end
      end

      # @api private
      def self.normalize_substitution(s)
        case s
        when TypeSubstitution
          s
        when ::Hash
          TypeSubstitution.new(
            from_type: s[:from_type] || s["from_type"],
            to_type: s[:to_type] || s["to_type"],
          )
        else
          raise ArgumentError, "Invalid substitution: #{s.inspect}"
        end
      end
    end
  end
end
