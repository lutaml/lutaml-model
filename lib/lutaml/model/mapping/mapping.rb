module Lutaml
  module Model
    class Mapping
      def initialize
        @mappings = []
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
