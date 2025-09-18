require_relative "mapping/model_mapping"

module Lutaml
  module Model
    class ModelTransformer
      class << self
        def source(source, options = {})
          @source = get_type(source)
          @source_options = options
        end

        def target(target, options = {})
          @target = get_type(target)
          @target_options = options
        end

        def transform(input = nil, &block)
          if input
            transform_to_target(input)
          elsif transformation_block?(block)
            @transform_method = block
          elsif @source <= Serialize || @target <= Serialize
            @mapping = ModelMapping.new(@source, @target, self)
            @mapping.instance_eval(&block)
          else
            raise UnknownTransformationTypeError, "Unknown Type of transformation for #{@source} to #{@target}"
          end
        end

        def reverse_transform(input = nil, &block)
          if input
            transform_to_source(input)
          elsif transformation_block?(block)
            @reverse_transform_method = block
          else
            raise ReverseTransformationDeclarationError, "Cannot declare reverse_transform for Model to Model transformation"
          end
        end

        private

        def transform_to_target(input)
          if @mapping
            transformed = @mapping.process_mappings(input)
            return @target.new(transformed)
          end

          if @transform_method.nil?
            raise TransformBlockNotDefinedError, "transform block not defined for #{@source} to  #{@target}"
          end

          @transform_method.call(input)
        end

        def transform_to_source(input)
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
          @source <= Type::Value || @target <= Type::Value || block&.arity&.positive?
        end

        def get_type(typ)
          case typ
          when Symbol
            if Type::TYPE_CODES[typ]
              Type.lookup(typ)
            else
              Object.const_get(typ.to_s)
            end
          when Class
            typ
          end
        end
      end
    end
  end
end
