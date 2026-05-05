module Lutaml
  module Model
    class Transformer
      class << self
        def call(value, rule, attribute, format: nil)
          new(rule, attribute, format).call(value)
        end

        private

        def get_transform_static(obj, direction)
          transform = obj&.transform
          return nil if transform.nil? || transform.is_a?(Class)

          transform.is_a?(::Hash) ? transform[direction] : transform
        end

        def apply_static(value, sources, direction, format)
          methods = sources.filter_map do |obj|
            get_transform_static(obj, direction)
          end

          class_transformers = sources.filter_map do |obj|
            next unless obj&.transform.is_a?(Class) &&
              obj.transform < Lutaml::Model::ValueTransformer

            obj.transform
          end

          return value if methods.empty? && class_transformers.empty?

          apply_direction = direction == :import ? :from : :to
          result = class_transformers.reduce(value) do |v, tc|
            tc.public_send(apply_direction, v, format)
          end

          methods.reduce(result) { |tv, m| m.call(tv) }
        end
      end

      attr_reader :rule, :attribute, :format

      def initialize(rule, attribute, format = nil)
        @rule = rule
        @attribute = attribute
        @format = format
      end

      def call(value)
        methods = transformation_methods

        class_transformers = ordered_sources.filter_map do |obj|
          next unless obj&.transform.is_a?(Class) &&
            obj.transform < Lutaml::Model::ValueTransformer

          obj.transform
        end

        result = class_transformers.reduce(value) do |v, transformer_class|
          apply_class_transformer(v, transformer_class, format)
        end

        methods.reduce(result) do |transformed_value, method|
          method.call(transformed_value)
        end
      end

      def apply_class_transformer(value, transformer_class, format)
        if instance_of?(ExportTransformer)
          transformer_class.to(value, format)
        else
          transformer_class.from(value, format)
        end
      end

      def get_transform(obj, direction)
        transform = obj&.transform
        return nil if transform.is_a?(Class)

        transform.is_a?(::Hash) ? transform[direction] : transform
      end
    end

    class ImportTransformer < Transformer
      class << self
        def call(value, rule, attribute, format: nil)
          apply_static(value, [rule, attribute], :import, format)
        end
      end

      def ordered_sources
        [rule, attribute]
      end

      def transformation_methods
        ordered_sources.filter_map { |obj| get_transform(obj, :import) }
      end
    end

    class ExportTransformer < Transformer
      class << self
        def call(value, rule, attribute, format: nil)
          apply_static(value, [attribute, rule], :export, format)
        end
      end

      def ordered_sources
        [attribute, rule]
      end

      def transformation_methods
        ordered_sources.filter_map { |obj| get_transform(obj, :export) }
      end
    end
  end
end
