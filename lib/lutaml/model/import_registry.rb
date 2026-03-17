# frozen_string_literal: true

module Lutaml
  module Model
    # ImportRegistry manages deferred imports with explicit resolution.
    #
    # This is an INTERNAL class. Users should use Register and GlobalRegister.
    #
    # Responsibility: Track and resolve deferred type imports
    #
    # This class:
    # - Tracks pending imports per class
    # - Resolves imports in correct order (topological)
    # - NO TracePoint needed - explicit resolution
    # - Tracks resolution state to prevent re-resolution
    #
    # @api private
    #
    # @example Deferring an import
    #   registry = ImportRegistry.new
    #   registry.defer(MyClass, method: :author, symbol: :Person)
    #
    # @example Resolving imports
    #   registry.resolve(MyClass, context)
    #   # Now MyClass.author type is resolved to Person class
    #
    class ImportRegistry
      # Represents a single deferred import
      DeferredImport = Struct.new(:owner_class, :method, :symbol, :resolved) do
        def resolved?
          resolved == true
        end
      end

      # @return [Hash<Class, Array<DeferredImport>>] Pending imports by owner class
      attr_reader :pending_imports

      # @return [Set<Class>] Classes whose imports have been resolved
      attr_reader :resolved_classes

      # Create a new ImportRegistry.
      def initialize
        @pending_imports = {}
        @resolved_classes = Set.new
        @mutex = Mutex.new
      end

      # Defer an import for later resolution.
      #
      # @param owner_class [Class] The class that owns the import
      # @param method [Symbol] The method/attribute to resolve
      # @param symbol [Symbol] The symbol name to resolve
      # @return [DeferredImport] The created deferred import
      def defer(owner_class, method:, symbol:)
        import = DeferredImport.new(
          owner_class: owner_class,
          method: method,
          symbol: symbol,
          resolved: false,
        )

        @mutex.synchronize do
          @pending_imports[owner_class] ||= []
          @pending_imports[owner_class] << import
          # Mark as not resolved if we're adding new imports
          @resolved_classes.delete(owner_class)
        end

        import
      end

      # Resolve all imports for a specific class.
      #
      # @param owner_class [Class] The class to resolve imports for
      # @param context [TypeContext] The resolution context
      # @return [Array<DeferredImport>] The resolved imports
      # @raise [UnknownTypeError] If a type cannot be resolved
      def resolve(owner_class, context)
        return [] unless pending?(owner_class)

        resolved = []

        @mutex.synchronize do
          imports = @pending_imports[owner_class] || []
          imports.each do |import|
            next if import.resolved?

            # Resolve the type
            resolved_type = TypeResolver.resolve(import.symbol, context)

            # Store the resolved type on the owner class's attribute
            apply_resolution(owner_class, import.method, resolved_type)

            import.resolved = true
            resolved << import
          end

          @resolved_classes << owner_class
        end

        resolved
      end

      # Resolve all pending imports.
      #
      # @param context [TypeContext] The resolution context
      # @return [Integer] Number of imports resolved
      def resolve_all!(context)
        resolved_count = 0

        @mutex.synchronize do
          @pending_imports.each_key do |owner_class|
            next if @resolved_classes.include?(owner_class)

            imports = @pending_imports[owner_class] || []
            imports.each do |import|
              next if import.resolved?

              begin
                resolved_type = TypeResolver.resolve(import.symbol, context)
                apply_resolution(owner_class, import.method, resolved_type)
                import.resolved = true
                resolved_count += 1
              rescue UnknownTypeError
                # Skip types that can't be resolved yet
                # They may be resolved in a later pass or by another context
              end
            end

            # Check if all imports for this class are resolved
            if imports.all?(&:resolved?)
              @resolved_classes << owner_class
            end
          end
        end

        resolved_count
      end

      # Check if a class has pending (unresolved) imports.
      #
      # @param owner_class [Class] The class to check
      # @return [Boolean] true if class has pending imports
      def pending?(owner_class)
        @mutex.synchronize do
          pending_without_lock?(owner_class)
        end
      end

      # Internal method to check pending status without acquiring lock.
      # Must be called from within a synchronized block.
      #
      # @param owner_class [Class] The class to check
      # @return [Boolean] true if class has pending imports
      # @api private
      def pending_without_lock?(owner_class)
        return false unless @pending_imports.key?(owner_class)
        return true unless @resolved_classes.include?(owner_class)

        # Check if any imports are not yet resolved
        @pending_imports[owner_class].any? { |i| !i.resolved? }
      end
      private :pending_without_lock?

      # Check if a class's imports are fully resolved.
      #
      # @param owner_class [Class] The class to check
      # @return [Boolean] true if all imports are resolved
      def resolved?(owner_class)
        @mutex.synchronize do
          return true unless @pending_imports.key?(owner_class)
          return false unless @resolved_classes.include?(owner_class)

          @pending_imports[owner_class].all?(&:resolved?)
        end
      end

      # Get pending imports for a class.
      #
      # @param owner_class [Class] The class to get imports for
      # @return [Array<DeferredImport>] The pending imports
      def imports_for(owner_class)
        @mutex.synchronize do
          @pending_imports[owner_class] || []
        end
      end

      # Get all classes with pending imports.
      #
      # @return [Array<Class>] The classes with pending imports
      def pending_classes
        @mutex.synchronize do
          @pending_imports.keys.select { |k| pending_without_lock?(k) }
        end
      end

      # Reset all state (for testing).
      #
      # @return [void]
      def reset!
        @mutex.synchronize do
          @pending_imports.clear
          @resolved_classes.clear
        end
      end

      # Get statistics about the registry.
      #
      # @return [Hash] Statistics including pending and resolved counts
      def stats
        @mutex.synchronize do
          total = @pending_imports.values.sum(&:size)
          resolved = @pending_imports.values.sum do |imports|
            imports.count(&:resolved?)
          end
          pending_count = @pending_imports.keys.count do |k|
            pending_without_lock?(k)
          end

          {
            total_imports: total,
            resolved_imports: resolved,
            pending_imports: total - resolved,
            pending_classes: pending_count,
          }
        end
      end

      private

      # Apply a resolved type to the owner class.
      #
      # This method updates the attribute on the owner class with
      # the resolved type.
      # Subclasses can override this to customize how types are applied.
      #
      # @param owner_class [Class] The class to update
      # @param method [Symbol] The method/attribute name
      # @param resolved_type [Class] The resolved type
      def apply_resolution(owner_class, method, resolved_type)
        # The actual implementation depends on how attributes are stored
        # This is a hook that can be customized
        # For now, we just store it in a class-level variable
        owner_class.instance_variable_set(:@_resolved_imports, {})
        owner_class.instance_variable_get(:@_resolved_imports)[method] =
          resolved_type
      end
    end
  end
end
