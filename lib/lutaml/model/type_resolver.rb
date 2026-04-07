# frozen_string_literal: true

module Lutaml
  module Model
    # TypeResolver performs stateless type resolution.
    #
    # This is an INTERNAL class. Users should use Register and GlobalRegister.
    #
    # Responsibility: Resolve type names to classes using pure logic
    #
    # This class:
    # - Is STATELESS - no instance variables, all methods are class methods
    # - Contains the single place for type resolution algorithm
    # - Resolution chain: primary registry → substitutions → fallback contexts
    # - NO caching, NO global state access
    # - Easy to test in isolation
    #
    # @api private
    #
    # @example Basic resolution
    #   context = TypeContext.default
    #   TypeResolver.resolve(:string, context)  #=> Lutaml::Model::Type::String
    #   TypeResolver.resolve(:unknown, context) #=> raises UnknownTypeError
    #
    # @example Resolution with fallbacks
    #   custom_registry = TypeRegistry.new
    #   custom_registry.register(:custom, MyCustomType)
    #   context = TypeContext.derived(
    #     id: :my_app,
    #     registry: custom_registry,
    #     fallback_to: [TypeContext.default]
    #   )
    #   TypeResolver.resolve(:custom, context)  #=> MyCustomType
    #   TypeResolver.resolve(:string, context)  #=> Lutaml::Model::Type::String (from fallback)
    #
    class TypeResolver
      # Resolve a type name to a class using the given context.
      #
      # Resolution order:
      # 1. If name is already a Class, return it (pass-through)
      # 2. Check primary registry
      # 3. Check substitutions (apply if matching)
      # 4. Check fallback contexts in order
      # 5. Raise UnknownTypeError if not found anywhere
      #
      # @param name [Symbol, String, Class] The type name or class to resolve
      # @param context [TypeContext] The resolution context
      # @return [Class] The resolved type class
      # @raise [UnknownTypeError] If type cannot be resolved
      #
      # @example
      #   TypeResolver.resolve(:string, context)  #=> Lutaml::Model::Type::String
      #   TypeResolver.resolve(MyClass, context)  #=> MyClass (pass-through)
      def self.resolve(name, context)
        # Apply substitutions even if already a class
        # This is important for type substitution (e.g., Glaze -> RegisterGlaze)
        if name.is_a?(Class)
          return apply_substitutions(name, context)
        end

        # Normalize name to symbol
        type_name = name.to_sym

        # 1. Check primary registry
        type = context.lookup_local(type_name)
        return apply_substitutions(type, context) if type

        # 2. Check fallback contexts in order
        if context.has_fallbacks?
          context.fallback_contexts.each do |fallback_context|
            type = resolve_from_fallback(type_name, fallback_context)
            return apply_substitutions(type, context) if type
          end
        end

        # 3. Fall back to legacy Type module's internal registry
        # This maintains backward compatibility with Type.register()
        type = Type.lookup_ignoring_fallback(type_name)
        return apply_substitutions(type, context) if type

        # 4. Try Type.const_get for CamelCase type names (e.g., "Decimal" -> Type::Decimal)
        # This maintains backward compatibility with old Register behavior
        if name.is_a?(String)
          begin
            type = Lutaml::Model::Type.const_get(name)
            return apply_substitutions(type, context) if type
          rescue NameError
            # Not a constant in Type module, continue to error
          end
        end

        # 5. Type not found - raise error
        raise UnknownTypeError.new(
          type_name,
          context_id: context.id,
          available_types: available_type_names(context),
        )
      end

      # Check if a type can be resolved without raising an exception.
      #
      # @param name [Symbol, String, Class] The type name or class to check
      # @param context [TypeContext] The resolution context
      # @return [Boolean] true if type can be resolved
      #
      # @example
      #   TypeResolver.resolvable?(:string, context)  #=> true
      #   TypeResolver.resolvable?(:unknown, context) #=> false
      def self.resolvable?(name, context)
        resolve(name, context)
        true
      rescue UnknownTypeError
        false
      end

      # Try to resolve a type, returning nil if not found.
      #
      # @param name [Symbol, String, Class] The type name or class to resolve
      # @param context [TypeContext] The resolution context
      # @return [Class, nil] The resolved type class or nil
      #
      # @example
      #   TypeResolver.resolve_or_nil(:string, context)  #=> Lutaml::Model::Type::String
      #   TypeResolver.resolve_or_nil(:unknown, context) #=> nil
      def self.resolve_or_nil(name, context)
        resolve(name, context)
      rescue UnknownTypeError
        nil
      end

      # Resolve from a fallback context (recursive).
      #
      # @param type_name [Symbol] The type name to resolve
      # @param fallback_context [TypeContext] The fallback context
      # @return [Class, nil] The resolved type or nil
      def self.resolve_from_fallback(type_name, fallback_context)
        # Check the fallback's local registry
        type = fallback_context.lookup_local(type_name)
        return type if type

        # Recursively check fallback's fallbacks
        if fallback_context.has_fallbacks?
          fallback_context.fallback_contexts.each do |nested_fallback|
            type = resolve_from_fallback(type_name, nested_fallback)
            return type if type
          end
        end

        nil
      end

      # Apply substitutions to a resolved type.
      #
      # @param type [Class] The resolved type
      # @param context [TypeContext] The context with substitutions
      # @return [Class] The type (possibly substituted)
      def self.apply_substitutions(type, context)
        return type if context.nil? || context.substitutions.empty?

        context.substitutions.each do |sub|
          substituted = sub.apply(type)
          return substituted if substituted
        end

        type
      end

      # Get all available type names from context and fallbacks.
      #
      # @param context [TypeContext] The resolution context
      # @return [Array<Symbol>] All available type names
      def self.available_type_names(context)
        names = context.registry.names.dup

        if context.has_fallbacks?
          context.fallback_contexts.each do |fallback|
            names.concat(fallback.registry.names)
          end
        end

        names.uniq.sort
      end
    end
  end
end
