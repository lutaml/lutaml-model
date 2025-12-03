module Lutaml
  module Model
    class NoAttributesDefinedLiquidError < Error
      def initialize(model_klass)
        super("#{model_klass} does not define any attributes for Liquid drop registration.")
      end
    end
  end
end
