module Lutaml
  module Model
    module Liquefiable
      def self.included(base)
        base.extend(ClassMethods)
      end

      module ClassMethods
        def register_liquid_drop_class
          validate_liquid!
          if drop_class
            raise "#{drop_class_name} Already exists!"
          end

          const_set(drop_class_name,
                    Class.new(Liquid::Drop) do
                      def initialize(object)
                        super()
                        @object = object
                      end
                    end)
        end

        def drop_class_name
          @drop_class_name ||= if name
                                 "#{to_s.split('::').last}Drop"
                               else
                                 "Drop"
                               end
        end

        def drop_class
          const_get(drop_class_name)
        rescue StandardError
          nil
        end

        def register_drop_method(method_name)
          register_liquid_drop_class unless drop_class
          return if drop_class.method_defined?(method_name)

          drop_class.define_method(method_name) do
            value = @object.public_send(method_name)

            if value.is_a?(Array)
              value.map(&:to_liquid)
            else
              value.to_liquid
            end
          end
        end

        def validate_liquid!
          return if Object.const_defined?(:Liquid)

          raise Lutaml::Model::LiquidNotEnabledError
        end
      end

      def to_liquid
        self.class.validate_liquid!

        if is_a?(Lutaml::Model::Serializable)
          self.class.attributes.each_key do |attr_name|
            self.class.register_drop_method(attr_name)
          end
        end
        self.class.drop_class.new(self)
      end
    end
  end
end
