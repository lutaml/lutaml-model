module Lutaml
  module Model
    class Transformer
      class << self
        def call(value, rule, attribute, format: :xml)
          new(rule, attribute, format).call(value)
        end
      end

      attr_reader :rule, :attribute, :format

      def initialize(rule, attribute, format = :xml)
        @rule = rule
        @attribute = attribute
        @format = format
      end

      def call(value)
        # Collect all class-based and hash/proc-based transformers
        # Apply them in the correct order based on transformation_methods

        # Get ordered transformation methods (already in correct precedence)
        methods = transformation_methods

        # Also check for class-based transformers and add them in correct order
        class_transformers = []
        if instance_of?(ExportTransformer)
          # Export order: attribute first, then rule
          class_transformers << attribute.transform if attribute&.transform.is_a?(Class) && attribute.transform < Lutaml::Model::ValueTransformer
          class_transformers << rule.transform if rule&.transform.is_a?(Class) && rule.transform < Lutaml::Model::ValueTransformer
        else
          # Import order: rule first, then attribute
          class_transformers << rule.transform if rule&.transform.is_a?(Class) && rule.transform < Lutaml::Model::ValueTransformer
          class_transformers << attribute.transform if attribute&.transform.is_a?(Class) && attribute.transform < Lutaml::Model::ValueTransformer
        end

        # Apply class transformers first, then hash/proc transformers
        result = class_transformers.reduce(value) do |v, transformer_class|
          apply_class_transformer(v, transformer_class, format)
        end

        # Then apply hash/proc transformers
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
      # Precedene of transformations:
      # 1. Rule transform
      # 2. Attribute transform
      def transformation_methods
        [
          get_transform(rule, :import),
          get_transform(attribute, :import),
        ].compact
      end
    end

    class ExportTransformer < Transformer
      # Precedene of transformations (reverse order):
      # 1. Attribute transform
      # 2. Rule transform
      def transformation_methods
        [
          get_transform(attribute, :export),
          get_transform(rule, :export),
        ].compact
      end
    end
  end
end
