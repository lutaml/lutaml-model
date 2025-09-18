module Lutaml
  module Model
    class ModelMappingRule
      attr_reader :name,
                  :from,
                  :to,
                  :collection,
                  :mapping

      def initialize(
        name = nil,
        from:,
        to:,
        transform: nil,
        reverse_transform: nil,
        mapping: nil
      )
        @name = name
        @from = from
        @to = to
        @transform = transform
        @reverse_transform = transform.is_a?(Class) && reverse_transform.nil? ? transform : reverse_transform
        @mapping = mapping
      end

      def transform_value(transformer, attr, value, reverse: false)
        if @mapping
          return @mapping.process_mappings(value, reverse: reverse)
        end

        if @reverse_transform && reverse
          transform_call(transformer, @reverse_transform, value, :reverse_transform)
        elsif @transform
          transform_call(transformer, @transform, value, :transform)
        else
          attr.type.cast(value)
        end
      end

      private

      def transform_call(transformer, transform, value, transform_method)
        case transform
        when Proc
          transform.call(value)
        when String, Symbol
          transformer.new.send(transform, value)
        when Class
          transform.public_send(transform_method, value)
        end
      end
    end
  end
end
