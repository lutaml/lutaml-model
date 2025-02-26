# frozen_string_literal: true

module Lutaml
  module Model
    class Register
      attr_accessor :id, :models

      def initialize(id)
        @id = id
        @models = {}
        @global_substitutions = {}
      end

      def register_model(name = nil, model = nil)
        raise ArgumentError, "missing `model` class to register" if model.nil? && name.nil?

        if name && model.nil? && name.is_a?(Class)
          @models[Utils.snake_case(name).to_sym] = name
        elsif name && model
          @models[name.to_sym] = model
        end
      end

      def resolve(klass_str)
        @models.values.find { |value| value if value.to_s == klass_str }
      end

      def get_class(klass_name)
        klass = if @models.key?(klass_name)
                  @models[klass_name]
                elsif klass_name.is_a?(String)
                  Lutaml::Model::Type.const_get(klass_name)
                else
                  Lutaml::Model::Type.lookup(klass_name)
                end
        raise UnkownTypeError.new(klass_name) if klass.nil?

        klass
      end

      def lookup(model)
        key = model.is_a?(Symbol) ? model : @models.key(model)
        @models[key]
      end

      def lookup?(model)
        if model.is_a?(Symbol)
          @models.key?(model)
        elsif model.is_a?(Class)
          @models.value?(model)
        end
      end

      def register_model_tree(model)
        raise InvalidModelClassError.new(model) unless model.is_a?(Symbol) || model < Lutaml::Model::Serializable
        raise UnexpectedModelReplacementError.new(model, @models.key(model)) if lookup?(model)

        register_model(model)
        require_tree(model.attributes)
      end

      def register_global_type_substitution(from_typ:, to_type:)
        @global_substitutions[from_type] = to_type
      end

      private

      def require_tree(attributes)
        attributes.each_value do |attribute|
          next if built_in_type?(attribute.resolved_type) || attribute.resolved_type.nil?

          register_model_tree(attribute.resolved_type)
        end
      end

      def built_in_type?(type)
        Lutaml::Model::Type::TYPE_CODES.value?(type.inspect) ||
          Lutaml::Model::Type::TYPE_CODES.key?(type.to_s.to_sym)
      end
    end
  end
end
