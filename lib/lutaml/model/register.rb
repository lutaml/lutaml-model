# frozen_string_literal: true

module Lutaml
  module Model
    # Register is a collection of models (types) for a specific context.
    #
    # Register is a MODEL TREE VERSIONING AND SUBSTITUTION SYSTEM.
    # It enables:
    # 1. Model Tree Versioning - Entire trees of related models work together
    # 2. Hierarchical Fallbacks - Nested registers can inherit from each other
    # 3. Global Substitution - Swap entire subtrees of models at once
    # 4. Composition - A document model can "compose" other model trees
    # 5. Namespace Binding - Registers can be bound to XML namespaces for versioning
    #
    # @example Creating a register with fallback
    #   register = Lutaml::Model::Register.new(:my_app, fallback: [:default])
    #   register.register_model(MyClass)
    #   register.register_model_tree(MyModelTree)
    #
    # @example Type substitution
    #   register.register_global_type_substitution(from: OldClass, to: NewClass)
    #
    # @example Resolution with fallback chain
    #   klass = register.get_class(:some_type)  # Resolves through fallback chain
    #
    # @example Namespace binding for version-aware resolution
    #   register.bind_namespace(Xmi::Namespace::Omg::Xmi20131001)
    #   klass = register.resolve_in_namespace(:documentation, namespace_uri)
    #
    # @see GlobalRegister For managing multiple registers
    # @see GlobalContext For context management and global operations
    # @see NamespaceBinding For namespace-to-register bindings
    #
    class Register
      # @return [Symbol] The register ID
      attr_reader :id

      # @return [Array<Symbol>] The fallback register IDs
      attr_reader :fallback

      # @return [Hash{String => NamespaceBinding}] Namespace URI to binding map
      attr_reader :bound_namespaces

      def initialize(id, fallback: nil)
        @id = id
        @fallback = determine_fallback(id, fallback)
        @global_substitutions = {} # For backward compatibility with tests
        @models = {} # For backward compatibility - survives GlobalContext.reset!
        @bound_namespaces = {} # Namespace URI => NamespaceBinding

        # Ensure context exists in GlobalContext
        ensure_context_exists
      end

      # Returns models hash (from internal storage for backward compatibility).
      # This survives GlobalContext.reset! which is needed for :xsd register.
      #
      # @return [Hash] Hash of registered models
      def models
        @models
      end

      # Register a model class.
      #
      # @param klass [Class] The class to register
      # @param id [Symbol, nil] Optional explicit ID (defaults to snake_case class name)
      # @return [Class] The registered class
      def register_model(klass, id: nil)
        model_id = id || Utils.base_class_snake_case(klass).to_sym

        # Type::Value subclasses go to global Type registry
        if klass <= Lutaml::Model::Type::Value
          return Lutaml::Model::Type.register(model_id, klass)
        end

        raise NotRegistrableClassError.new(klass) unless klass.include?(Lutaml::Model::Registrable)

        # Store in internal hash (survives GlobalContext.reset!)
        @models[model_id.to_sym] = klass
        @models[klass.to_s] = klass

        # Register in GlobalContext
        ctx = global_context
        if ctx && !ctx.registry.registered?(model_id)
          ctx.registry.register(model_id, klass)
        end

        # Also register by class name for backward compatibility
        if ctx
          klass_name = klass.to_s
          unless ctx.registry.registered?(klass_name.to_sym)
            ctx.registry.register(klass_name.to_sym, klass)
          end
        end

        klass
      end

      # Resolve a class by string representation.
      #
      # @param klass_str [String, Symbol, Class] The class name or class
      # @return [Class, nil] The class or nil
      def resolve(klass_str)
        # If already a class, return it directly
        return klass_str if klass_str.is_a?(Class)

        ctx = global_context
        return nil unless ctx

        # Try exact string match first
        result = ctx.registry.lookup(klass_str.to_sym)
        return result if result

        # Try as class name
        ctx.registry.names.each do |name|
          klass = ctx.registry.lookup(name)
          return klass if klass && klass.to_s == klass_str
        end

        nil
      end

      # Get a class by name, setting the register on the class.
      #
      # @param klass_name [Symbol, String, Class] The type name or class
      # @return [Class] The resolved class
      # @raise [UnknownTypeError] If type cannot be resolved
      def get_class(klass_name)
        expected_class = get_class_without_register(klass_name)

        # Only set @register if it's not already set
        if !(expected_class < Lutaml::Model::Type::Value) &&
            !expected_class.instance_variable_defined?(:@register)
          expected_class.instance_variable_set(:@register, id)
        end

        expected_class
      end

      # Register a model and all its nested attribute types.
      #
      # @param klass [Class] The model class
      def register_model_tree(klass)
        register_model(klass)
        if klass.include?(Lutaml::Model::Serialize)
          register_attributes(klass.attributes)
        end
      end

      # Register a type substitution.
      #
      # @param from_type [Class, Symbol] Type to substitute from
      # @param to_type [Class, Symbol] Type to substitute to
      def register_global_type_substitution(from_type:, to_type:)
        # Store in internal hash for backward compatibility with tests
        @global_substitutions[from_type] = to_type
        # Also register in GlobalContext for actual type resolution
        GlobalContext.registry.register_substitution(@id, from_type, to_type)
      end

      # Register all non-builtin types from attributes.
      #
      # @param attributes [Hash] The attributes hash
      def register_attributes(attributes)
        attributes.each_value do |attribute|
          next unless attribute.unresolved_type.is_a?(Class)
          next if built_in_type?(attribute.unresolved_type) || attribute.unresolved_type.nil?

          register_model_tree(attribute.unresolved_type)
        end
      end

      # Check if a class has a substitution.
      #
      # @param klass [Class] The class to check
      # @return [Boolean] true if substitutable
      def substitutable?(klass)
        ctx = global_context
        return false unless ctx

        ctx.substitutions.any? { |sub| sub.applies_to?(klass) }
      end

      # Get the substitution for a class.
      #
      # @param klass [Class] The class to substitute
      # @return [Class, nil] The substituted type or nil
      def substitute(klass)
        ctx = global_context
        return nil unless ctx

        ctx.substitutions.each do |sub|
          result = sub.apply(klass)
          return result if result && result != klass
        end

        nil
      end

      # Check if to_type is a registered substitution for from_type.
      #
      # @param from_type [Class] Type to substitute from
      # @param to_type [Class] Type to substitute to
      # @return [Boolean] true if this substitution exists
      def substituted_type_for?(from_type, to_type)
        ctx = global_context
        return false unless ctx

        ctx.substitutions.any? do |sub|
          sub.applies_to?(from_type) && sub.to_type == to_type
        end
      end

      # Get class without setting register.
      #
      # @param klass_name [Symbol, String, Class] The type name or class
      # @return [Class] The resolved class
      # @raise [UnknownTypeError] If type cannot be resolved
      def get_class_without_register(klass_name)
        # If already a class, apply substitutions and return
        return apply_substitutions(klass_name) if klass_name.is_a?(Class)

        # Only Symbol and String are valid type names
        unless klass_name.is_a?(Symbol) || klass_name.is_a?(String)
          raise UnknownTypeError.new(klass_name)
        end

        # Use GlobalContext for resolution (handles fallbacks via TypeContext)
        begin
          result = GlobalContext.resolve_type(klass_name, @id)
          return apply_substitutions(result)
        rescue UnknownTypeError
          # Fall through to try other methods
        end

        # Try Type.const_get for CamelCase names (backward compatibility)
        if klass_name.is_a?(String)
          begin
            result = Lutaml::Model::Type.const_get(klass_name)
            return apply_substitutions(result)
          rescue NameError
            # Fall through
          end
        end

        # Try Type.lookup
        begin
          result = Lutaml::Model::Type.lookup(klass_name.to_sym)
          return apply_substitutions(result)
        rescue UnknownTypeError
          # Fall through
        end

        raise UnknownTypeError.new(klass_name)
      end

      # Clear type class cache.
      def clear_type_class_cache
        GlobalContext.clear_caches
      end

      # Clear all global type substitutions.
      def clear_global_substitutions
        @global_substitutions.clear
      end

      # =====================================================================
      # Namespace Binding Methods
      # =====================================================================

      # @api public
      # Bind this register to a namespace class.
      #
      # This enables version-aware type resolution where different namespaces
      # can map to different type implementations.
      #
      # @param namespace_class [Class] A Lutaml::Xml::Namespace subclass
      # @return [NamespaceBinding] The created binding
      # @raise [ArgumentError] If namespace_class is not a Lutaml::Xml::Namespace
      #
      # @example
      #   register.bind_namespace(Xmi::Namespace::Omg::Xmi20131001)
      def bind_namespace(namespace_class)
        binding = Lutaml::Model::NamespaceBinding.new(
          register_id: @id,
          namespace_class: namespace_class,
        )

        @bound_namespaces[namespace_class.uri] = binding

        # Register in GlobalContext for reverse lookup
        GlobalContext.bind_register_to_namespace(@id, namespace_class.uri)

        binding
      end

      # @api public
      # Check if this register handles a specific namespace URI.
      #
      # @param namespace_uri [String] The namespace URI to check
      # @return [Boolean] true if this register is bound to this namespace
      def handles_namespace?(namespace_uri)
        @bound_namespaces.key?(namespace_uri)
      end

      # @api public
      # Get all bound namespace URIs.
      #
      # @return [Array<String>] List of namespace URIs
      def bound_namespace_uris
        @bound_namespaces.keys
      end

      # @api public
      # Get namespace binding for a URI.
      #
      # @param namespace_uri [String] The namespace URI
      # @return [NamespaceBinding, nil] The binding or nil
      def namespace_binding(namespace_uri)
        @bound_namespaces[namespace_uri]
      end

      # @api public
      # Resolve type with namespace-aware fallback.
      #
      # If the namespace is handled by this register, tries to resolve
      # the type locally first. Falls back to the fallback chain if not found.
      #
      # @param type_name [Symbol, String] The type name
      # @param namespace_uri [String, nil] The namespace URI (optional)
      # @return [Class, nil] The resolved class or nil
      #
      # @example
      #   klass = register.resolve_in_namespace(:documentation, "http://...")
      def resolve_in_namespace(type_name, namespace_uri = nil)
        # If namespace specified and this register handles it
        if namespace_uri && handles_namespace?(namespace_uri)
          result = safe_get_class(type_name)
          return result if result
        end

        # Try fallback chain
        @fallback&.each do |fallback_id|
          result = resolve_in_fallback(fallback_id, type_name, namespace_uri)
          return result if result
        end

        nil
      end

      # @api public
      # Import a model tree with optional namespace binding.
      #
      # Recursively registers the root class and all nested attribute types.
      # If a namespace is provided, binds the register to that namespace.
      #
      # @param root_class [Class] The root model class
      # @param namespace [Class, nil] Optional namespace class for binding
      # @return [Array<Class>] All registered classes
      #
      # @example
      #   register.import_model_tree(Xmi::V20131001::Model, namespace: XmiNamespace)
      def import_model_tree(root_class, namespace: nil)
        importer = Lutaml::Model::ModelTreeImporter.new(self, namespace_class: namespace)
        importer.import(root_class)
      end

      private

      def global_context
        GlobalContext.context(@id)
      end

      def ensure_context_exists
        return if GlobalContext.context(@id)

        GlobalContext.create_context(
          id: @id,
          fallback_to: @fallback,
        )
      end

      def built_in_type?(type)
        Lutaml::Model::Type::TYPE_CODES.value?(type.inspect) ||
          Lutaml::Model::Type::TYPE_CODES.key?(type.to_s.to_sym)
      end

      def determine_fallback(id, explicit_fallback)
        return [] if explicit_fallback == [] # Explicit isolation
        return explicit_fallback if explicit_fallback # Explicit fallback
        return [] if id == :default # Default has no fallback

        [:default] # Non-default registers fallback to default
      end

      def apply_substitutions(klass)
        return klass unless klass.is_a?(Class)

        substituted = substitute(klass)
        substituted || klass
      end

      def safe_get_class(type_name)
        get_class_without_register(type_name)
      rescue UnknownTypeError
        nil
      end

      def resolve_in_fallback(fallback_id, type_name, namespace_uri)
        fallback_register = GlobalRegister.lookup(fallback_id)
        return nil unless fallback_register

        fallback_register.resolve_in_namespace(type_name, namespace_uri)
      end
    end

    # Reopen Register class to add autoload for error class and new classes
    class Register
      autoload :NotRegistrableClassError,
               "#{File.dirname(__FILE__)}/error/register/not_registrable_class_error"
      autoload :NamespaceBinding,
               "#{File.dirname(__FILE__)}/register/namespace_binding"
      autoload :ModelTreeImporter,
               "#{File.dirname(__FILE__)}/register/model_tree_importer"
    end
  end
end
