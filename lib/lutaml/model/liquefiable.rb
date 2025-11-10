require_relative "liquid/mapping"

module Lutaml
  module Model
    module Liquefiable
      def self.included(base)
        base.extend(ClassMethods)
        base.register_class_if_liquid_defined
      end

      module ClassMethods
        attr_writer :mappings

        def inherited(child)
          super
          child.register_class_if_liquid_defined
          child.mappings = Utils.deep_dup(mappings) || {}
        end

        def register_class_if_liquid_defined
          return unless is_a?(Class)
          return unless Object.const_defined?(:Liquid)
          return if base_drop_class

          register_liquid_drop_class
        end

        def liquid_class(class_name)
          @custom_liquid_class_name = class_name
        end

        def custom_liquid_class_name
          @custom_liquid_class_name
        end

        def register_liquid_drop_class
          validate_liquid!
          if base_drop_class
            raise "#{drop_class_name} Already exists!"
          end

          const_set(drop_class_name,
                    Class.new(::Liquid::Drop) do
                      def initialize(object)
                        super()
                        @object = object
                      end
                    end)
        end

        def drop_class_name
          @drop_class_name ||= if name
                                 "#{name.split('::').last}Drop"
                               else
                                 "Drop"
                               end
        end

        def base_drop_class
          const_get(drop_class_name)
        rescue StandardError
          nil
        end

        def drop_class
          if custom_liquid_class_name
            begin
              return Object.const_get(custom_liquid_class_name)
            rescue NameError
              raise Lutaml::Model::LiquidClassNotFoundError, custom_liquid_class_name
            end
          end

          base_drop_class
        end

        def to_liquid_class
          register_methods unless @methods_generated

          base_drop_class
        end

        def register_methods
          @methods_generated = true

          if self <= Serializable
            raise Lutaml::Model::NoAttributesDefinedLiquidError.new(name) if attributes.empty?

            register_drop_method(:element_order)

            attributes&.each_key { |attr_name| register_drop_method(attr_name) }
          end

          generate_mapping_methods
        end

        def register_drop_method(method_name)
          return if base_drop_class.method_defined?(method_name)

          base_drop_class.define_method(method_name) do
            value = @object.public_send(method_name)

            if value.is_a?(Array)
              value.map(&:to_liquid)
            else
              value.to_liquid
            end
          end
        end

        def generate_mapping_methods
          return unless liquid_mappings&.mappings

          liquid_mappings.mappings.each do |key, method_name|
            base_drop_class.define_method(key) do
              value = @object.public_send(method_name)

              if value.is_a?(Array)
                value.map(&:to_liquid)
              else
                value.to_liquid
              end
            end
          end
        end

        def liquid(&block)
          return unless Object.const_defined?(:Liquid)

          mappings[:liquid] ||= ::Lutaml::Model::Liquid::Mapping.new
          mappings[:liquid].instance_eval(&block) if block
          mappings[:liquid]
        end

        def liquid_mappings
          mappings[:liquid]
        end

        def mappings
          @mappings ||= {}
        end

        def validate_liquid!
          return if Object.const_defined?(:Liquid)

          raise Lutaml::Model::LiquidNotEnabledError
        end
      end

      def to_liquid
        self.class.validate_liquid!

        self.class.register_methods

        self.class.drop_class.new(self)
      end
    end
  end
end
