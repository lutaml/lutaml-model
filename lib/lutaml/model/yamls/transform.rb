module Lutaml
  module Model
    module Yamls
      class Transform < Lutaml::Model::KeyValueTransform
        def data_to_model(data, format, options = {})
          mappings = defined_mappings_for(:yamls) || mappings_for(:yaml)

          super(data, format, options.merge(mappings: mappings))
        end

        def model_to_data(instance, _format, options = {})
          # For YAMLS collections, use yamls mappings for this collection
          # But let nested instances use their own yaml mappings
          # by passing :yaml format without forcing mappings parameter
          defined_mappings_for(:yamls) || mappings_for(:yaml)

          # Override format to :yaml - nested instances will auto-select yaml mappings
          super(instance, :yaml, options)
        end
      end
    end
  end
end
