require_relative "mapping/model_mapping"

module Lutaml
  module Model
    class ModelTransformer
      class << self
        def source(source)
          @source = get_type(source)
        end

        def target(target)
          @target = get_type(target)
        end

        def transform(input = nil, mapping: false, &block)
          if input
            transform_to_target(input, mapping: mapping)
          elsif transformation_block?(block)
            @transform_method = block
          else
            @mapping = ModelMapping.new(@source, @target, self)
            @mapping.instance_eval(&block)
          end
        end

        def reverse_transform(input = nil, mapping: false, &block)
          if input
            transform_to_source(input, mapping: mapping)
          elsif transformation_block?(block)
            @reverse_transform_method = block
          else
            raise ReverseTransformationDeclarationError, "Cannot declare reverse_transform for Model to Model transformation"
          end
        end

        private

        def transform_to_target(input, mapping: false)
          return input.map { |i| transform_to_target(i) } if input.is_a?(Array) && !mapping

          if @mapping
            transformed = @mapping.process_mappings(input)
            return @target.new(transformed)
          end

          if @transform_method.nil?
            raise TransformBlockNotDefinedError, "transform block not defined for #{@source} to #{@target}"
          end

          @transform_method.call(input)
        end

        def transform_to_source(input, mapping: false)
          return input.map { |i| transform_to_source(i) } if input.is_a?(Array) && !mapping

          if @mapping
            transformed = @mapping.process_mappings(input, reverse: true)
            return @source.new(transformed)
          end

          if @reverse_transform_method.nil?
            raise ReverseTransformBlockNotDefinedError, "reverse_transform block not defined for #{@target} to #{@source}"
          end

          @reverse_transform_method.call(input)
        end

        def transformation_block?(block)
          (@source.is_a?(Class) && @source <= Type::Value) ||
            (@target.is_a?(Class) && @target <= Type::Value) ||
            block&.arity&.positive?
        end

        def get_type(typ)
          case typ
          when Symbol
            if Type::TYPE_CODES[typ]
              Type.lookup(typ)
            else
              raise Lutaml::Model::UnknownTypeError, "Unsupported type #{typ} for transformation"
            end
          when Class
            typ
          end
        end
      end
    end
  end
end
