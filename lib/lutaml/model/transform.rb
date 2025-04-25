module Lutaml
  module Model
    class Transform
      def self.data_to_model(context, data, format, options = {})
        new(context, options[:register]).data_to_model(data, format, options)
      end

      def self.model_to_data(context, model, format, options = {})
        new(context, model.register).model_to_data(model, format, options)
      end

      attr_reader :context, :attributes, :register

      def initialize(context, register = nil)
        @context = context
        @attributes = context.attributes
        @register = register || Lutaml::Model::Config.default_register
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

      def apply_value_map(value, value_map, attr)
        if value.nil?
          value_for_option(value_map[:nil], attr)
        elsif Utils.empty?(value)
          value_for_option(value_map[:empty], attr, value)
        elsif Utils.uninitialized?(value)
          value_for_option(value_map[:omitted], attr)
        else
          value
        end
      end

      def value_for_option(option, attr, empty_value = nil)
        return nil if option == :nil
        return empty_value || empty_object(attr) if option == :empty

        Lutaml::Model::UninitializedClass.instance
      end

      def empty_object(attr)
        return [] if attr.collection?

        ""
      end

      def mappings_for(format)
        context.mappings_for(format)
      end

      def valid_rule?(rule)
        attribute = attribute_for_rule(rule)

        !!attribute || rule.custom_methods[:from]
      end

      def attribute_for_rule(rule)
        return attributes[rule.to] unless rule.delegate

        attributes[rule.delegate].resolved_type(register).attributes[rule.to]
      end

      def register_accessor_methods_for(object, register)
        klass = object.class
        Utils.add_method_if_not_defined(klass, :register) do
          @register
        end
        Utils.add_method_if_not_defined(klass, :register=) do |value|
          @register = value
        end
        object.register = register
      end
    end
  end
end

require_relative "transform/key_value_transform"
require_relative "transform/xml_transform"
