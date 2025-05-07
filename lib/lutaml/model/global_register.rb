# frozen_string_literal: true

module Lutaml
  module Model
    class GlobalRegister
      include Singleton

      def initialize
        default_register = Lutaml::Model::Register.new(:default)
        @registers = { default_register.id => default_register }
      end

      def register(model_register)
        @registers[model_register.id] = model_register
      end

      def lookup(id)
        @registers[id.to_sym]
      end

      def registered_objects
        @registers.values
      end

      class << self
        def register(model_register)
          instance.register(model_register)
        end

        def lookup(id)
          instance.lookup(id)
        end

        def registered_objects
          instance.registered_objects
        end
      end
    end
  end
end
