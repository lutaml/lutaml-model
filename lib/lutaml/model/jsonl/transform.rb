module Lutaml
  module Model
    module Jsonl
      class Transform < Lutaml::Model::KeyValueTransform
        def data_to_model(data, format, options = {})
          mappings = defined_mappings_for(:jsonl) || mappings_for(:json)

          super(data, format, options.merge(mappings: mappings))
        end

        def model_to_data(instance, format, options = {})
          mappings = defined_mappings_for(:jsonl) || mappings_for(:json)

          super(instance, format, options.merge(mappings: mappings))
        end
      end
    end
  end
end
