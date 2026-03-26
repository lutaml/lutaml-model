# frozen_string_literal: true

module Lutaml
  module Model
    class Transform
      def self.data_to_model(context, data, format, options = {})
        new(context, options[:register]).data_to_model(data, format, options)
      end

      def self.model_to_data(context, model, format, options = {})
        register = model.lutaml_register if model.respond_to?(:lutaml_register)
        new(context, register).model_to_data(model, format, options)
      end

      attr_reader :context, :attributes, :lutaml_register

      def initialize(context, register = nil)
        @context = context
        @lutaml_register = register || Lutaml::Model::Config.default_register
        @attributes = context.attributes(lutaml_register)
      end

      def model_class
        @context.model
      end

      def data_to_model(data, options = {})
        raise NotImplementedError,
              "#{self.class.name} must implement `data_to_model`."
      end

      def model_to_data(model, options = {})
        raise NotImplementedError,
              "#{self.class.name} must implement `model_to_data`."
      end

      protected

      def apply_value_map(value, value_map, attr)
        if value.nil?
          value_for_option(value_map[:nil], attr)
        elsif Utils.empty?(value)
          # Check for boolean value_map format (value_map[:empty] is true/false)
          # Only apply for Boolean type attributes
          if value_map[:empty].is_a?(TrueClass) || value_map[:empty].is_a?(FalseClass)
            # Check if attribute is a Boolean type
            attr_type = attr&.type || attr&.unresolved_type
            if attr_type == Lutaml::Model::Type::Boolean
              return value_map[:empty]
            end
          end
          value_for_option(value_map[:empty], attr, value)
        elsif Utils.uninitialized?(value)
          # Check for boolean value_map format (value_map[:omitted] is true/false)
          # Only apply for Boolean type attributes
          if value_map[:omitted].is_a?(TrueClass) || value_map[:omitted].is_a?(FalseClass)
            # Check if attribute is a Boolean type
            attr_type = attr&.type || attr&.unresolved_type
            if attr_type == Lutaml::Model::Type::Boolean
              return value_map[:omitted]
            end
          end
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

      def mappings_for(format, register = nil)
        context.mappings_for(format, register)
      end

      def defined_mappings_for(format)
        context.mappings[format]
      end

      def valid_rule?(rule, attribute)
        attribute || rule.custom_methods[:from]
      end

      def attribute_for_rule(rule)
        return attributes[rule.to] unless rule.delegate

        attributes[rule.delegate].type(lutaml_register).attributes[rule.to]
      end

      def register_accessor_methods_for(object, register)
        klass = object.class
        Utils.add_method_if_not_defined(klass, :lutaml_register) do
          @lutaml_register
        end
        Utils.add_method_if_not_defined(klass, :lutaml_register=) do |value|
          @lutaml_register = value
        end
        object.lutaml_register = register
      end

      def root_and_parent_assignment(instance, options)
        root_and_parent_accessor_methods_for(instance)
        return unless options.key?(:lutaml_parent) && options.key?(:lutaml_root)

        instance.lutaml_root = options[:lutaml_root] || options[:lutaml_parent]
        instance.lutaml_parent = options[:lutaml_parent]
      end

      def root_and_parent_accessor_methods_for(instance)
        Utils.add_accessor_if_not_defined(instance.class, :lutaml_parent)
        Utils.add_accessor_if_not_defined(instance.class, :lutaml_root)
      end
    end
  end
end
