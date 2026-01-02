require_relative "base"

module Lutaml
  module Model
    module Services
      class DefaultValueResolver < Base
        def initialize(attribute, register, instance_object)
          super()

          @attribute = attribute
          @register = register
          @instance_object = instance_object
        end

        # Get the default value with proper instance context and casting
        # Returns the evaluated and casted default value
        def default
          attribute.cast_value(default_value, register)
        end

        # Get the default value with proper instance context
        # Returns the evaluated default value (procs are executed)
        def default_value
          raw_value = raw_default_value
          return raw_value unless raw_value.is_a?(Proc)

          # Execute proc in instance context if available, otherwise call it directly
          if instance_object
            instance_object.instance_exec(&raw_value)
          else
            raw_value.call
          end
        end

        # Get the raw default value without executing procs
        def raw_default_value
          if attribute.delegate
            # For delegated attributes, recursively resolve through the service
            delegated_attr = attribute.type(register).attributes[attribute.to]
            self.class.new(delegated_attr, register, instance_object).raw_default_value
          elsif attribute.options.key?(:default)
            attribute.options[:default]
          else
            Lutaml::Model::UninitializedClass.instance
          end
        end

        # Check if a default value is set (not uninitialized)
        def default_set?
          !Utils.uninitialized?(raw_default_value)
        end

        private

        attr_reader :attribute, :register, :instance_object
      end
    end
  end
end
