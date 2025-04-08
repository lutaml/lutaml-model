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

      def register_model(klass, id: nil)
        add_model_in_register(klass, id)
      end

      def register_model!(klass, id: nil)
        raise Lutaml::Model::Register::InvalidModelClassError.new(klass) unless klass < Lutaml::Model::Serialize
        raise Lutaml::Model::Register::UnexpectedModelReplacementError.new(klass, @models.key(klass)) if lookup?(klass)

        add_model_in_register(klass, id)
      end

      def resolve(klass_str)
        @models.values.find { |value| value.to_s == klass_str }
      end

      def get_class(klass_name)
        if @models.key?(klass_name)
          @models[klass_name]
        elsif resolvable?(klass_name)
          resolve(klass_name)
        elsif klass_name.is_a?(String)
          Lutaml::Model::Type.const_get(klass_name)
        elsif klass_name.is_a?(Symbol)
          Lutaml::Model::Type.lookup(klass_name)
        elsif klass_name.is_a?(Module)
          klass_name
        else
          raise Lutaml::Model::UnknownTypeError.new(klass_name)
        end
      end

      def lookup(klass)
        @models[klass.is_a?(Symbol) ? klass : @models.key(klass)]
      end

      def register_model_tree(klass)
        register_model(klass)
        require_tree(klass.attributes)
      end

      def register_model_tree!(klass)
        register_model!(klass)
        require_tree!(klass.attributes)
      end

      # Expected functionality for global type substitution
      # register.register_global_type_substitution(
      #   from_type: OldType,
      #   to_type: NewType
      # )
      # # Replace all Mml::Mi instances with Plurimath equivalents
      # register.register_global_type_substitution(
      #   from_type: Mml::Mi,
      #   to_type: Plurimath::Math::Symbols::Symbol
      # )
      def register_global_type_substitution(from_type:, to_type:)
        @global_substitutions[from_type] = to_type
      end

      def process_attributes(attributes, strict: false)
        register_method = strict ? :register_model_tree! : :register_model_tree

        attributes.each_value do |attribute|
          next if built_in_type?(attribute.resolved_type) || attribute.resolved_type.nil?

          send(register_method, attribute.resolved_type)
        end
      end

      private

      def add_model_in_register(klass, id)
        if id.nil?
          @models[Utils.base_class_snake_name(klass).to_sym] = klass
        else
          @models[id.to_sym] = klass
        end
      end

      def require_tree(attributes)
        attributes.each_value do |attribute|
          next if built_in_type?(attribute.resolved_type) || attribute.resolved_type.nil?

          register_model_tree(attribute.resolved_type)
        end
      end

      def require_tree!(attributes)
        attributes.each_value do |attribute|
          next if built_in_type?(attribute.resolved_type) || attribute.resolved_type.nil?

          register_model_tree!(attribute.resolved_type)
        end
      end

      def built_in_type?(type)
        Lutaml::Model::Type::TYPE_CODES.value?(type.inspect) ||
          Lutaml::Model::Type::TYPE_CODES.key?(type.to_s.to_sym)
      end

      def resolvable?(klass_str)
        @models.values.any? { |value| value.to_s == klass_str }
      end

      def lookup?(klass)
        case klass
        when Symbol then @models.key?(klass)
        when Module then @models.value?(klass)
        else false
        end
      end
    end
  end
end
