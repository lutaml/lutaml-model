module Lutaml
  module Model
    class Mapping
      def initialize
        @mappings = []
        @listeners = {} # target => [Listener, ...]
        @parent_mapping = nil
      end

      # Get listeners for a specific target (element name/key).
      #
      # @param target [String, Symbol] The element name or key
      # @return [Array<Lutaml::Model::Listener>] Listeners for the target
      def listeners_for(target)
        target_str = target.to_s if target
        @listeners[target_str] ||= []
      end

      # Add a listener to this mapping.
      #
      # @param listener [Lutaml::Model::Listener] The listener to add
      # @return [void]
      def add_listener(listener)
        listeners_for(listener.target) << listener
      end

      # Get all listeners across all targets.
      #
      # @return [Array<Lutaml::Model::Listener>] All listeners
      def all_listeners
        @listeners.values.flatten.freeze
      end

      # Remove ALL listeners for a given target.
      #
      # @param target [String, Symbol] The element name or key
      # @return [void]
      def omit_element(target)
        target_str = target.to_s if target
        @listeners.delete(target_str)
      end

      # Remove a specific listener by ID.
      #
      # @param target [String, Symbol] The element name or key
      # @param id [Symbol, String] The listener ID to remove
      # @return [void]
      def omit_listener(target, id:)
        listeners_for(target).reject! { |l| l.id == id }
      end

      # Inherit listeners from another mapping class.
      #
      # This copies all listeners from the parent mapping into this one.
      # When override by ID is needed, the child's listener takes precedence.
      #
      # @param parent [Class] A Lutaml::Model::Mapping subclass
      # @return [void]
      def inherit_from(parent)
        @parent_mapping = parent
      end

      # Get the parent mapping class if any.
      #
      # @return [Class, nil]
      def parent_mapping
        @parent_mapping
      end

      def mappings
        raise NotImplementedError,
              "#{self.class.name} must implement `mappings`."
      end

      def ensure_mappings_imported!(register_id = nil)
        return if @mappings_imported

        register_id ||= Lutaml::Model::Config.default_register
        importable_mappings.each do |model|
          import_model_mappings(
            Lutaml::Model::GlobalContext.resolve_type(model, register_id),
            register_id,
          )
        end
      end

      private

      def model_importable?(model)
        model.is_a?(Symbol) || model.is_a?(String)
      end

      def import_mappings_later(model)
        importable_mappings << model.to_sym
        @mappings_imported = false
      end

      def importable_mappings
        @importable_mappings ||= []
      end
    end
  end
end
