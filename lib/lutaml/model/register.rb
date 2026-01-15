# frozen_string_literal: true

module Lutaml
  module Model
    class Register
      attr_reader :id, :models, :fallback

      def initialize(id, fallback: nil)
        @id = id
        @models = {}
        @fallback = determine_fallback(id, fallback)
        @global_substitutions = {}
        @type_class_cache = {}
      end

      def register_model(klass, id: nil)
        id ||= Utils.base_class_snake_case(klass).to_sym
        if klass <= Lutaml::Model::Type::Value
          return Lutaml::Model::Type.register(id, klass)
        end
        raise NotRegistrableClassError.new(klass) unless klass.include?(Lutaml::Model::Registrable)

        @models[id.to_sym] = klass
        @models[klass.to_s] = klass
      end

      def resolve(klass_str)
        @models[klass_str.to_s]
      end

      def get_class(klass_name)
        expected_class = get_class_without_register(klass_name)
        # Only set @register if it's not already set (module-namespaced classes have it pre-set)
        if !(expected_class < Lutaml::Model::Type::Value) && !expected_class.instance_variable_defined?(:@register)
          expected_class.instance_variable_set(:@register, id)
        end
        expected_class
      end

      def register_model_tree(klass)
        register_model(klass)
        if klass.include?(Lutaml::Model::Serialize)
          register_attributes(klass.attributes)
        end
      end

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

      def get_class_without_register(klass_name)
        klass = extract_class_from(klass_name)
        raise Lutaml::Model::UnknownTypeError.new(klass_name) unless klass

        substitute(klass) || substitute(klass_name) || klass
      end

      private

      def get_type_class(klass_name)
        if klass_name.is_a?(String)
          Lutaml::Model::Type.const_get(klass_name)
        elsif klass_name.is_a?(Symbol)
          Lutaml::Model::Type.lookup(klass_name)
        end
      end

      def built_in_type?(type)
        Lutaml::Model::Type::TYPE_CODES.value?(type.inspect) ||
          Lutaml::Model::Type::TYPE_CODES.key?(type.to_s.to_sym)
      end

      def extract_class_from(klass)
        return klass if klass.is_a?(Class)
        return @models[klass] if @models.key?(klass)

        # Check cache first
        return @type_class_cache[klass] if @type_class_cache.key?(klass)

        # If not in cache, try to get type class and cache it
        begin
          if type_klass = get_type_class(klass)
            @type_class_cache[klass] = type_klass
            return type_klass
          end
        rescue Lutaml::Model::UnknownTypeError
          # Type not in global Type registry, will try fallback chain
        end

        # Try fallback chain (check @models directly to avoid Type lookup)
        @fallback.each do |fallback_id|
          next if fallback_id == @id  # Prevent circular reference
          fallback_register = Lutaml::Model::GlobalRegister.lookup(fallback_id)
          # Direct @models check, then recurse if not found
          if fallback_register.models.key?(klass)
            return fallback_register.models[klass]
          elsif result = fallback_register.extract_class_from(klass) rescue nil
            return result
          end
        end

        nil
      end

      def clear_type_class_cache
        @type_class_cache.clear
      end

      def determine_fallback(id, explicit_fallback)
        return [] if explicit_fallback == []  # Explicit isolation
        return explicit_fallback if explicit_fallback  # Explicit fallback
        return [] if id == :default  # Default has no fallback
        [:default]  # Non-default registers fallback to default
      end
    end
  end
end
