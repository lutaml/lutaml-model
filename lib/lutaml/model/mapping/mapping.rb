module Lutaml
  module Model
    class Mapping
      def initialize
        @mappings = []
        @importable_mappings = []
        @mappings_imported = ::Hash.new { |h, k| h[k] = false }
      end

      def mappings
        raise NotImplementedError,
              "#{self.class.name} must implement `mappings`."
      end

      def ensure_mappings_imported!(register_id = nil)
        register_object = register(register_id)
        return if @mappings_imported[register_object.id]

        importable_mappings.each do |model|
          __import_model_mappings(
            register_object.get_class_without_register(model),
            register_object.id,
          )
        end
      end

      private

      attr_accessor :importable_mappings

      def register(register_id = nil)
        register_id ||= Lutaml::Model::Config.default_register
        Lutaml::Model::GlobalRegister.lookup(register_id)
      end

      def model_importable?(model)
        model.is_a?(Symbol) || model.is_a?(String)
      end

      def import_mappings_later(model, register_id)
        register_object = register(register_id)
        importable_mappings << model.to_sym
        @mappings_imported[register_object.id] = false
      end
    end
  end
end
