module Lutaml
  module Model
    module Jsonl
      class Transform < Lutaml::Model::KeyValueTransform
        def data_to_model(data, format, options = {})
          mappings = defined_mappings_for(:jsonl) || mappings_for(:json, __register)

          super(data, format, options.merge(mappings: mappings))
        end

        def model_to_data(instance, _format, options = {})
          # For JSONL collections, use jsonl mappings for this collection
          # But let nested instances use their own json mappings
          # by passing :json format without forcing mappings parameter
          defined_mappings_for(:jsonl) || mappings_for(:json, __register)

          # Override format to :json - nested instances will auto-select json mappings
          super(instance, :json, options)
        end
      end
    end
  end
end
