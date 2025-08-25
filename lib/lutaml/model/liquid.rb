require_relative "liquid/mapping"
require_relative "transform"

module Lutaml
  module Model
    module Liquid
      class Transform < Lutaml::Model::Transform
        # Liquid doesn't need data transformation since it's only
        # used for configuring drop methods
        def data_to_model(data, format, options = {})
          raise NotImplementedError, "Liquid format is for drop configuration only"
        end

        def model_to_data(instance, format, options = {})
          raise NotImplementedError, "Liquid format is for drop configuration only"
        end
      end
    end
  end
end
