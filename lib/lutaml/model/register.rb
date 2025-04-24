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
        return register_in_type(klass, id) if klass < Lutaml::Model::Type::Value

        add_model_in_register(klass, id)
      end

      def register_model!(klass, id: nil)
        return register_in_type(klass, id) if klass < Lutaml::Model::Type::Value
        raise Lutaml::Model::Register::InvalidModelClassError.new(klass) unless klass < Lutaml::Model::Serialize
        raise Lutaml::Model::Register::UnexpectedModelReplacementError.new(klass, @models.key(klass)) if lookup?(klass)

        add_model_in_register(klass, id)
      end

      def resolve(klass_str)
        @models.values.find { |value| value.to_s == klass_str }
      end

      def get_class(klass_name)
        klass = if @models.key?(klass_name)
                  @models[klass_name]
                elsif resolvable?(klass_name)
                  resolve(klass_name)
                elsif type_klass = get_type_class(klass_name)
                  type_klass
                elsif klass_name.is_a?(Module)
                  klass_name
                end
        # Temporarily raising error.
        raise Lutaml::Model::UnknownTypeError.new(klass_name) unless klass

        klass
      end

      def lookup(klass)
        @models[klass.is_a?(Symbol) ? klass : @models.key(klass)]
      end

      def register_model_tree(klass)
        register_model(klass)
        if klass < Lutaml::Model::Serializable
          register_attributes(klass.attributes)
        end
      end

      def register_model_tree!(klass)
        register_model!(klass)
        if klass < Lutaml::Model::Serializable
          register_attributes(klass.attributes, strict: true)
        end
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

      def register_attributes(attributes, strict: false)
        register_method = strict ? :register_model_tree! : :register_model_tree

        attributes.each_value do |attribute|
          next if built_in_type?(attribute.resolved_type(self)) || attribute.resolved_type(self).nil?

          public_send(register_method, attribute.resolved_type(self))
        end
      end

      private

      def get_type_class(klass_name)
        if klass_name.is_a?(String)
          Lutaml::Model::Type.const_get(klass_name)
        elsif klass_name.is_a?(Symbol)
          Lutaml::Model::Type.lookup(klass_name)
        end
      end

      def register_in_type(klass, id)
        id ||= Lutaml::Model::Utils.base_class_snake_name(klass).to_sym
        Lutaml::Model::Type.register(id, klass)
      end

      def add_model_in_register(klass, id)
        if id.nil?
          @models[Utils.base_class_snake_name(klass).to_sym] = klass
        else
          @models[id.to_sym] = klass
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
