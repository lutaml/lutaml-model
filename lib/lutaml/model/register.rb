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

      def resolve(klass_str)
        return unless resolvable?(klass_str)

        @models.values.find { |value| value.to_s == klass_str }
      end

      def get_class(klass_name)
        klass = if @models.key?(klass_name)
                  @models[klass_name]
                elsif resolvable?(klass_name)
                  resolve(klass_name)
                elsif type_klass = get_type_class(klass_name)
                  type_klass
                elsif klass_name.is_a?(Class)
                  klass_name
                end
        raise Lutaml::Model::UnknownTypeError.new(klass_name) unless klass

        if substitutable?(klass)
          substitute(klass)
        elsif substitutable?(klass_name)
          substitute(klass_name)
        else
          klass
        end
      end

      def register_model_tree(klass)
        register_model(klass)
        if klass.include?(Lutaml::Model::Registrable)
          register_attributes(klass.attributes)
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

      def register_attributes(attributes)
        attributes.each_value do |attribute|
          next unless attribute.unresolved_type.is_a?(Class)
          next if built_in_type?(attribute.unresolved_type) || attribute.unresolved_type.nil?

          register_model_tree(attribute.unresolved_type)
        end
      end

      def substitutable?(klass)
        @global_substitutions.key?(klass)
      end

      def substitute(klass)
        @global_substitutions[klass]
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
    end
  end
end
