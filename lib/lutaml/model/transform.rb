module Lutaml
  module Model
    class Transform
      def self.data_to_model(context, data, format, options = {})
        new(context).data_to_model(data, format, options)
      end

      def self.model_to_data(context, model, format, options = {})
        new(context).model_to_data(model, format, options)
      end

      attr_reader :context, :attributes

      def initialize(context)
        @context = context
        @attributes = context.attributes
      end

      def model_class
        @context.model
      end

      def data_to_model(data, options = {})
        raise NotImplementedError, "#{self.class.name} must implement `data_to_model`."
      end

      def model_to_data(model, options = {})
        raise NotImplementedError, "#{self.class.name} must implement `model_to_data`."
      end

      protected

      def mappings_for(format)
        context.mappings_for(format)
      end

      def valid_rule?(rule)
        attribute = attribute_for_rule(rule)

        !!attribute || rule.custom_methods[:from]
      end

      def attribute_for_rule(rule)
        return attributes[rule.to] unless rule.delegate

        attributes[rule.delegate].type.attributes[rule.to]
      end
    end
  end
end

require_relative "transform/key_value_transform"
require_relative "transform/xml_transform"
