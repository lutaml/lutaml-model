module Lutaml
  module Model
    class Transformer
      class << self
        def call(value, rule, attribute, format: nil, context: nil)
          new(rule, attribute, format, context).call(value)
        end

        private

        def get_transform_static(obj, direction)
          transform = obj&.transform
          return nil if transform.nil? || transform.is_a?(Class)

          transform.is_a?(::Hash) ? transform[direction] : transform
        end

        def apply_static(value, sources, direction, format, context = nil)
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

          methods.reduce(result) do |tv, m|
            if m.arity == 2
              m.call(tv, context)
            else
              m.call(tv)
            end
          end
        end
      end

      attr_reader :rule, :attribute, :format, :context

      def initialize(rule, attribute, format = nil, context = nil)
        @rule = rule
        @attribute = attribute
        @format = format
        @context = context
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
          invoke_transform(method, transformed_value)
        end
      end

      # lutaml-model#550: `with:` custom methods opt into the options
      # passed to `from_*` / `to_*` by declaring a second parameter
      # (exact arity 2); one-parameter methods keep the historical
      # single-argument call.
      def invoke_transform(method, value)
        if method.arity == 2
          method.call(value, context)
        else
          method.call(value)
        end
      end

      def apply_class_transformer(value, transformer_class, format)
        if export_direction?
          transformer_class.to(value, format)
        else
          transformer_class.from(value, format)
        end
      end

      def export_direction?
        false
      end

      def get_transform(obj, direction)
        transform = obj&.transform
        return nil if transform.is_a?(Class)

        transform.is_a?(::Hash) ? transform[direction] : transform
      end
    end

    class ImportTransformer < Transformer
      class << self
        def call(value, rule, attribute, format: nil, context: nil)
          apply_static(value, [rule, attribute], :import, format, context)
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
        def call(value, rule, attribute, format: nil, context: nil)
          apply_static(value, [attribute, rule], :export, format, context)
        end
      end

      def ordered_sources
        [attribute, rule]
      end

      def transformation_methods
        ordered_sources.filter_map { |obj| get_transform(obj, :export) }
      end

      def export_direction?
        true
      end
    end
  end
end
