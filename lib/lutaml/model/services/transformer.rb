module Lutaml
  module Model
    class Transformer
      class << self
        def call(value, rule, attribute)
          new(rule, attribute).call(value)
        end
      end

      attr_reader :rule, :attribute

      def initialize(rule, attribute)
        @rule = rule
        @attribute = attribute
      end

      def call(value)
        transformation_methods.reduce(value) do |transformed_value, method|
          method.call(transformed_value)
        end
      end
    end

    class ImportTransformer < Transformer
      # Precedene of transformations:
      # 1. Rule transform
      # 2. Attribute transform
      def transformation_methods
        [
          rule.transform[:import],
          attribute&.transform&.[](:import),
        ].compact
      end
    end

    class ExportTransformer < Transformer
      # Precedene of transformations (reverse order):
      # 1. Attribute transform
      # 2. Rule transform
      def transformation_methods
        [
          attribute&.transform&.[](:export),
          rule.transform[:export],
        ].compact
      end
    end
  end
end
