# frozen_string_literal: true

module Lutaml
  module Model
    class GlobalRegister
      include Singleton

      def initialize
        @registers = {}
        default_register = Lutaml::Model::Register.new(:default)
        register(default_register)
      end

      def register(model_register)
        @registers[model_register.id] = model_register
      end

      def lookup(id)
        @registers[id.to_sym]
      end

      def remove(id)
        @registers.delete(id.to_sym)
      end

      class << self
        def register(model_register)
          instance.register(model_register)
        end

        def lookup(id)
          instance.lookup(id)
        end

        def remove(id)
          instance.remove(id)
        end
      end
    end
  end
end
