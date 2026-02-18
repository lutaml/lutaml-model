# frozen_string_literal: true

module Lutaml
  module Model
    # GlobalRegister is a singleton facade for managing all Register instances.
    #
    # This is the primary entry point for register management:
    # - Store and retrieve Register instances
    # - Clear caches for testing
    # - Manage the default register
    #
    # @example Registering and looking up registers
    #   register = Lutaml::Model::Register.new(:my_app)
    #   Lutaml::Model::GlobalRegister.register(register)
    #   found = Lutaml::Model::GlobalRegister.lookup(:my_app)
    #
    # @example Managing registers
    #   Lutaml::Model::GlobalRegister.remove(:my_app)
    #   Lutaml::Model::GlobalRegister.instance.reset  # Clear caches
    #
    # @see Register For creating and using registers
    # @see GlobalContext For context management and global operations
    #
    class GlobalRegister
      include Singleton

      def initialize
        @registers = {} # Store original Register instances for backward compatibility

        # Ensure :default register exists
        default_register = Register.new(:default)
        @registers[:default] = default_register
      end

      # Register a Register instance.
      #
      # @param model_register [Register] The register to register
      # @return [Register] The register (for backward compatibility)
      def register(model_register)
        @registers[model_register.id] = model_register
        model_register
      end

      # Look up a register by ID.
      #
      # @param id [Symbol, Register] The register ID or Register instance
      # @return [Register, nil] The register or nil
      def lookup(id)
        # Handle both Register instances and symbol/string IDs
        id = id.id if id.is_a?(Register)

        @registers[id.to_sym]
      end

      # Remove a register by ID.
      #
      # @param id [Symbol] The register ID
      def remove(id)
        register_id = id.to_sym

        # Clear type cache entries for this specific register on all models
        # We need to find all registered models in this context
        ctx = GlobalContext.context(register_id)
        if ctx
          ctx.registry.names.each do |name|
            model_class = ctx.registry.lookup(name)
            if model_class.respond_to?(:clear_cache)
              model_class.clear_cache(register_id)
            end
          end
        end

        # Remove from internal @registers hash
        @registers.delete(register_id)

        # Also clean up GlobalContext
        GlobalContext.unregister_context(register_id)
      end
      alias unregister :remove

      # Clear type cache on all models in all registers.
      #
      # Useful for test cleanup to prevent test pollution.
      def clear_all_model_caches
        GlobalContext.clear_caches
      end

      # Clear all caches and reset.
      #
      # This is useful for testing to prevent test pollution.
      def reset
        # Clear GlobalContext caches (but not the contexts themselves)
        GlobalContext.clear_caches

        # Reset default_register to :default if it was changed
        if Lutaml::Model::Config.default_register != :default
          Lutaml::Model::Config.default_register = :default
        end
      end

      class << self
        def register(model_register)
          instance.register(model_register)
        end

        def lookup(id)
          instance.lookup(id)
        end

        def remove(id)
          instance.remove(id)
        end

        def unregister(id)
          instance.remove(id)
        end
      end
    end
  end
end
