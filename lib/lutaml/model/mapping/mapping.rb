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

        register_object = register(register_id)
        importable_mappings.each do |model|
          import_model_mappings(
            register_object.get_class_without_register(model),
            register_object.id,
          )
        end
      end

      private

      def register(register_id = nil)
        register_id ||= Lutaml::Model::Config.default_register
        Lutaml::Model::GlobalRegister.lookup(register_id)
      end

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
